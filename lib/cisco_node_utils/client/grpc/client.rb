#!/usr/bin/env ruby
#
# October 2015, Glenn F. Matthews
#
# Copyright (c) 2015-2016 Cisco and/or its affiliates.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require_relative '../client'
Cisco::Client.silence_warnings do
  require 'grpc'
end
require 'json'
require_relative 'ems_services'

include IOSXRExtensibleManagabilityService
include Cisco::Logger

# Client implementation using gRPC API for IOS XR
class Cisco::Client::GRPC < Cisco::Client
  register_client(self)

  attr_accessor :timeout

  def initialize(address, username, password)
    # TODO: remove if/when we have a local socket to use
    if address.nil? && username.nil? && password.nil? && ENV['NODE']
      address ||= ENV['NODE'].split(' ')[0]
      username ||= ENV['NODE'].split(' ')[1]
      password ||= ENV['NODE'].split(' ')[2]
    end
    super(address:      address,
          username:     username,
          password:     password,
          data_formats: [:cli, :yangpathjson],
          platform:     :ios_xr)
    @config = GRPCConfigOper::Stub.new(address, :this_channel_is_insecure)
    @exec = GRPCExec::Stub.new(address, :this_channel_is_insecure)

    # Make sure we can actually connect
    @timeout = 5
    begin
      base_msg = 'gRPC client creation failure: '
      get(command: 'show clock')
    rescue Cisco::ClientError => e
      error 'initial connect failed: ' + e.to_s
      if e.message[/deadline exceeded/i]
        raise Cisco::ConnectionRefused, \
              base_msg + 'timed out during initial connection: ' + e.message
      end
      raise e.class, base_msg + e.message
    end

    # Let commands in general take up to 2 minutes
    @timeout = 120
  end

  def validate_args(address, username, password)
    super
    base_msg = 'gRPC client creation failure: '
    fail TypeError, base_msg + 'address must be specified' if address.nil?
    fail ArgumentError, base_msg + 'port # required in address' \
         unless address[/:/]
    # Connection to remote system - username and password are required
    fail TypeError, base_msg + 'username must be specified' if username.nil?
    fail TypeError, base_msg + 'password must be specified' if password.nil?
  end

  def rmyang(data_format: :yangjson,
          context:     nil,
          values:      nil)
    debug "values ====> #{values}"
    args = ConfigArgs.new(yangjson: values)
    reqyang(@config, 'delete_config', args)
  end
 
  def replaceyang(data_format: :yangjson,
          values:      nil)
    debug "values ====> #{values}"
    args = ConfigArgs.new(yangjson: values)
    reqyang(@config, 'replace_config', args)
  end

  def setyang(data_format: :yangjson,
          values:      nil)
    debug "values @@====> #{values}"
    args = ConfigArgs.new(yangjson: values)
    reqyang(@config, 'merge_config', args)
  end
 
  def getyang(data_format: :yangpathjson,
          command:     nil,
             value: nil)
    fail ArgumentError if command.nil?
    copy = command.dup
    copy.gsub! '[null]', value
    args = ConfigGetArgs.new(yangpathjson: copy)
    debug "Cmd ====> #{command}"
    debug "Copy ====> #{copy}"
    debug "VALUE ====> #{value}"
    reqyang(@config, 'get_config', args)
  end

  def reqyang(stub, type, args)
    debug "Sending '#{type}' request:"
    if args.is_a?(ConfigGetArgs) 
      debug "  with yangpathjson: '#{args.yangpathjson}'"
    end
    if args.is_a?(ConfigArgs)
      debug " with yangjson: '#{args.yangjson}'"
    end
    output = Cisco::Client.silence_warnings do
      response = stub.send(type, args,
                           timeout:  @timeout,
                           username: @username,
                           password: @password)
      # gRPC server may split the response into multiples
      response = response.is_a?(Enumerator) ? response.to_a : [response]
      debug "Got responses: #{response.map(&:class).join(', ')}"
      debug "args ====> #{args}"
      debug "response =====> #{response}"
      # Check for errors first
      handle_errors(args, response.select { |r| !r.errors.empty? })

      # If we got here, no errors occurred
      handle_response(args, response)
    end
    return output

  rescue ::GRPC::BadStatus => e
    warn "gRPC error '#{e.code}' during '#{type}' request: "
    if args.is_a?(ConfigGetArgs)
      warn "  with yangpathjson: '#{args.yangpathjson}'"
    end
    warn "  '#{e.details}'"
    case e.code
    when ::GRPC::Core::StatusCodes::UNAVAILABLE
      raise Cisco::ConnectionRefused, "Connection refused: #{e.details}"
    when ::GRPC::Core::StatusCodes::UNAUTHENTICATED
      raise Cisco::AuthenticationFailed, e.details
    else
      raise Cisco::ClientError, e.details
    end
  end

  def handle_response(args, replies)
    klass = replies[0].class
    unless replies.all? { |r| r.class == klass }
      fail Cisco::ClientError, 'reply class inconsistent: ' +
        replies.map(&:class).join(', ')
    end
    debug "Handling #{replies.length} '#{klass}' reply(s):"
    case klass.to_s
    when /ShowCmdTextReply/
      replies.each { |r| debug "  output:\n#{r.output}" }
      output = replies.map(&:output).join('')
      output = handle_text_output(args, output)
    when /ShowCmdJSONReply/
      # TODO: not yet supported by server to test against
      replies.each { |r| debug "  jsonoutput:\n#{r.jsonoutput}" }
      output = replies.map(&:jsonoutput).join("\n---\n")
    when /ConfigGetReply/
      replies.each { |r| debug "  yangjson:\n#{r.yangjson}" }
      output = replies.map(&:yangjson).join('')
    when /ConfigReply/
      # nothing process
      output = ''
    when /CliConfigReply/
      # nothing to process
      output = ''
    else
      fail Cisco::ClientError, "unsupported reply class #{klass}"
    end
    debug "Success with output:\n#{output}"
    output
  end

  def handle_text_output(args, output)
    # For a successful show command, gRPC presents the output as:
    # \n--------- <cmd> ----------
    # \n<output of command>
    # \n\n

    # For an invalid CLI, gRPC presents the output as:
    # \n--------- <cmd> --------
    # \n<cmd>
    # \n<error output>
    # \n\n

    # Discard the leading whitespace, header, and trailing whitespace
    output = output.split("\n").drop(2)
    return '' if output.nil? || output.empty?

    # Now we have either [<output_line_1>, <output_line_2>, ...] or
    # [<cmd>, <error_line_1>, <error_line_2>, ...]
    if output[0].strip == args.cli.strip
      fail Cisco::CliError.new( # rubocop:disable Style/RaiseArgs
        rejected_input: args.cli,
        clierror:       output.join("\n"),
      )
    end
    output.join("\n")
  end

  def handle_errors(args, error_responses)
    return if error_responses.empty?
    debug "#{error_responses.length} response(s) had errors:"
    error_responses.each { |r| debug "  error:\n#{r.errors}" }
    first_error = error_responses.first.errors
    # Conveniently for us, all *Reply protobufs in EMS have an errors field
    # Less conveniently, some are JSON and some are not.
    begin
      msg = JSON.parse(first_error)
      handle_json_error(msg)
    rescue JSON::ParserError
      handle_text_error(args, first_error)
    end
  end

  # Generate an error from a failed request
  def handle_text_error(args, msg)
    if /^Disallowed commands:/ =~ msg
      fail Cisco::RequestNotSupported, msg
    else
      fail Cisco::CliError.new( # rubocop:disable Style/RaiseArgs
        rejected_input: args.cli,
        clierror:       msg,
      )
    end
  end

  # Generate a CliError from a failed CliConfigReply
  def handle_json_error(msg)
    # {
    #   "cisco-grpc:errors": {
    #   "error": [
    #     {
    #       "error-type": "application",
    #       "error-tag": "operation-failed",
    #       "error-severity": "error",
    #       "error-message": "....",
    #     },
    #     {
    #       ...

    # {
    #   "cisco-grpc:errors": [
    #     {
    #       "error-type": "protocol",
    #       "error-message": "Failed authentication"
    #     }
    #   ]
    # }

    msg = msg['cisco-grpc:errors']
    msg = msg['error'] unless msg.is_a?(Array)
    msg.each do |m|
      type = m['error-type']
      message = m['error-message']
      if type == 'protocol' && message == 'Failed authentication'
        fail Cisco::AuthenticationFailed, message
      elsif type == 'application'
        # Example message:
        # !! SYNTAX/AUTHORIZATION ERRORS: This configuration failed due to
        # !! one or more of the following reasons:
        # !!  - the entered commands do not exist,
        # !!  - the entered commands have errors in their syntax,
        # !!  - the software packages containing the commands are not active,
        # !!  - the current user is not a member of a task-group that has
        # !!    permissions to use the commands.
        #
        # foo
        # bar
        #
        match = /\n\n(.*)\n\n\Z/m.match(message)
        if match.nil?
          rejected = '(unknown, see error message)'
        else
          rejected = match[1].split("\n")
        end
        fail Cisco::CliError.new( # rubocop:disable Style/RaiseArgs
          rejected_input: rejected,
          clierror:       message,
        )
      else
        fail Cisco::ClientError, message
      end
    end
  end
end
