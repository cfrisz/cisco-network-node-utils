# CiscoNodeUtils - Cisco Node Utilities

[![Gem Version](https://badge.fury.io/rb/cisco_node_utils.svg)](http://badge.fury.io/rb/cisco_node_utils)
[![Build Status](https://travis-ci.org/cisco/cisco-network-node-utils.svg?branch=develop)](https://travis-ci.org/cisco/cisco-network-node-utils)

--
##### Documentation Workflow Map

This workflow map aids *users*, *developers* and *maintainers* of the CiscoNodeUtils project in selecting the appropriate document(s) for their task.

* User Guides - the remainder of this document is aimed at end users
* Developer Guides
  * [CONTRIBUTING.md](CONTRIBUTING.md) : Contribution guidelines
  * [README-develop-node-utils-APIs.md](docs/README-develop-node-utils-APIs.md) : Developing new CiscoNodeUtils APIs
  * [README-develop-best-practices.md](docs/README-develop-best-practices.md) : Development best practices
  * [README-develop-add-XR-support.md](docs/README-develop-add-XR-support.md) : How To Update node_utils APIs to Support IOS XR
* Maintainers Guides
  * [README-maintainers.md](docs/README-maintainers.md) : Guidelines for core maintainers of the CiscoNodeUtils project
  * All developer guides apply to maintainers as well

Please see [Learning Resources](#resources) for additional references.

--
#### Table of Contents

1. [Overview](#overview)
1. [Installation](#installation)
1. [Configuration](#configuration)
1. [Documentation](#documentation)
1. [Examples](#examples)
1. [Changelog](#changelog)
1. [Learning Resources](#resources)
1. [License Information](#license_info)


## <a name="overview">Overview</a>

The CiscoNodeUtils gem provides utilities for management of Cisco network
nodes. It is designed to work with Puppet and Chef as well as other
open source management tools.

This CiscoNodeUtils gem release supports the following:

Platform         | OS     | OS Version           |
-----------------|--------|----------------------|
Cisco Nexus 30xx | NX-OS  | 7.0(3)I2(1) and later
Cisco Nexus 31xx | NX-OS  | 7.0(3)I2(1) and later
Cisco Nexus 93xx | NX-OS  | 7.0(3)I2(1) and later
Cisco Nexus 95xx | NX-OS  | 7.0(3)I2(1) and later
Cisco N9kv       | NX-OS  | 7.0(3)I2(1) and later
Cisco Nexus 56xx | NX-OS  | 7.3(0)N1(1) and later
Cisco Nexus 60xx | NX-OS  | 7.3(0)N1(1) and later
Cisco Nexus 7xxx | NX-OS  | 7.3(0)D1(1) and later
TODO             | IOS XR | TODO


Please note: For Cisco Nexus 3k and 9k platforms, a virtual Nexus N9000/N3000 may be helpful for development and testing. Users with a valid [cisco.com](http://cisco.com) user ID can obtain a copy of a virtual Nexus N9000/N3000 by sending their [cisco.com](http://cisco.com) user ID in an email to <get-n9kv@cisco.com>. If you do not have a [cisco.com](http://cisco.com) user ID please register for one at [https://tools.cisco.com/IDREG/guestRegistration](https://tools.cisco.com/IDREG/guestRegistration)

## <a name="installation">Installation</a>

To install the CiscoNodeUtils, use the following command:

    $ gem install cisco_node_utils

(Add `sudo` if you're installing under a POSIX system as root)

Alternatively, if you've checked the source out directly, you can call
`rake install` from the root project directory.

## Configuration

Depending on the installation environment (Linux, NX-OS, or IOS XR), this gem may require configuration in order to be used. Two configuration file locations are supported:

* `/etc/cisco_node_utils.yaml` (system and/or root user configuration)
* `~/cisco_node_utils.yaml` (per-user configuration)

If both files exist and are readable, configuration in the user-specific file will take precedence over the system configuration.

This file specifies the host, port, username, and/or password to be used to connect to one or more nodes.

* When installing this gem on NX-OS nodes, this file is generally not needed, as the default client behavior is sufficient.
* When installing this gem on IOS XR nodes, this file needs to specify an IOS XR administrator `username` and `password` for the local (`default`) node. Additionally, if the gRPC server is configured to listen on a port other than its default of 57400, the `port` number must be specified in this file. *For security purposes, it is highly recommended that access to this file be restricted to only the owning user (`chmod 0600`).*
* When developing for or testing this gem, this file can specify one or more NX-OS and/or IOS XR nodes to run tests against. In this case:
  - A node labeled as `default` will be the default node to test against.
  - Nodes with other names can be selected at test execution time.
  - NX-OS nodes must be defined with a `host` (hostname or IP address), `username`, and `password`.
  - IOS XR nodes must be defined with a `host`, `username`, and `password`, plus a `port` if the gRPC server is listening on a non-default port.

An example configuration file (illustrating each of the above scenarios) is provided with this gem at [`docs/cisco_node_utils.yaml.example`](docs/cisco_node_utils.yaml.example).

## <a name="documentation">Documentation</a>

### Client

The `Client` class provides a low-level interface for communicating with the Cisco network node. It provides the base APIs `create`, `get`, and `set`. Currently there are two subclasses:

* `Cisco::Client::NXAPI` - client for communicating with NX-OS 7.0(3)I2(1) and later, using NX-API.
* `Cisco::Client::GRPC` - client for communicating with IOS XR 6.0.0 and later, using gRPC.

For a greater level of abstraction, the `Node` class is generally used, but the `Client` classes can be invoked directly if desired.

### Node

The `Node` class is a singleton which wraps around the `Client` class to provide for management of a given Cisco network node. It provides the base APIs `config_set`, `config_get`, and `config_get_default`.

### CommandReference

The `CommandReference` class abstracts away the differences between various supported `Node` types, be that API differences (CLI vs. YANG), platform differences (NX-OS vs. IOS XR), or hardware differences (Nexus 9xxx vs. Nexus 3xxx). A series of YAML files describe various `feature` groupings. Each file describes a set of `attributes` of the given feature and the specifics of how to inspect and manage these attributes for any supported `Node` types.  When a `Node` is connected, the platform identification of the Node is used to construct a `CommandReference` instance containing a set of `CmdRef` objects specific to this `Node`. The `Node` APIs `config_set`, `config_get`, and `config_get_default` all rely on the `CmdRef`.

See also [README_YAML](lib/cisco_node_utils/cmd_ref/README_YAML.md).

### Feature Providers

Each feature supported by CiscoNodeUtils has its own class. For example,
`Cisco::RouterOspf` is the class used to manage OSPF router configuration on
a `Node`. Each feature class has getters and setters which are wrappers around
the Node APIs `config_set`, `config_get`, and `config_get_default`.

### Puppet and Chef

This library is designed as a shared backend between Puppet and Chef for the
management of Cisco nodes. Puppet providers and Chef providers alike can use
the feature provider classes from this module to do the majority of work in
actually managing device configuration and state. This reduces the amount of
code duplication between the Cisco Puppet modules and the Cisco Chef cookbooks.

Generally speaking, Puppet and Chef should only interact with the feature
provider classes, and not directly call into `CommandReference` or `Node`.

## <a name="examples">Examples</a>


These utilities can be used directly on a Cisco device (as used by Puppet
and Chef) or can run on a workstation and point to a Cisco device (as used
by the included minitest suite).

### Usage on a Cisco device

#### Low-level Client API

```ruby
require 'cisco_node_utils'

# get a connection to the local device
client = Cisco::Client.create()

client.get(command: 'show version')
client.set(values: 'vtp domain mycompany.com')
```

#### High-level Node API

```ruby
require 'cisco_node_utils'

# get a connection to the local device
node = Cisco::Node.instance()

version = node.config_get("show_version", "system_image")

node.config_set("vtp", "domain", "mycompany.com")
```

### Remote usage

#### Low-level Client API

```ruby
require 'cisco_node_utils'

client = Cisco::Client.create('n3k.mycompany.com', 'username', 'password')

client.get(command: 'show version')
client.set(values: 'vtp domain mycompany.com')
```

#### High-level Node API

```ruby
require 'cisco_node_utils'

node = Cisco::Node.new("n3k.mycompany.com", "username", "password")

version = node.config_get("show_version", "system_image")

node.config_set("vtp", "domain", "mycompany.com")
```


## <a name="changelog">Changelog</a>


See [CHANGELOG](CHANGELOG.md) for a list of changes.


## <a name="resources">Learning Resources</a>


* Chef
  * [https://learn.chef.io/](https://learn.chef.io/)
  * [https://en.wikipedia.org/wiki/Chef_(software)](https://en.wikipedia.org/wiki/Chef_(software))
* Puppet
  * [https://learn.puppetlabs.com/](https://learn.puppetlabs.com/)
  * [https://en.wikipedia.org/wiki/Puppet_(software)](https://en.wikipedia.org/wiki/Puppet_(software))
* Markdown (for editing documentation)
  * [https://help.github.com/articles/markdown-basics/](https://help.github.com/articles/markdown-basics/)
* Ruby
  * [https://en.wikipedia.org/wiki/Ruby_(programming_language)](https://en.wikipedia.org/wiki/Ruby_(programming_language))
  * [https://www.codecademy.com/tracks/ruby](https://www.codecademy.com/tracks/ruby)
  * [https://rubymonk.com/](https://rubymonk.com/)
  * [https://www.codeschool.com/paths/ruby](https://www.codeschool.com/paths/ruby)
* Ruby Gems
  * [http://guides.rubygems.org/](http://guides.rubygems.org/)
  * [https://en.wikipedia.org/wiki/RubyGems](https://en.wikipedia.org/wiki/RubyGems)
* YAML
  * [https://en.wikipedia.org/wiki/YAML](https://en.wikipedia.org/wiki/YAML)
  * [http://www.yaml.org/start.html](http://www.yaml.org/start.html)
* Yum
  * [https://en.wikipedia.org/wiki/Yellowdog_Updater,_Modified](https://en.wikipedia.org/wiki/Yellowdog_Updater,_Modified)
  * [https://www.centos.org/docs/5/html/yum/](https://www.centos.org/docs/5/html/yum/)
  * [http://www.linuxcommand.org/man_pages](http://www.linuxcommand.org/man_pages/yum8.html)

## <a name="license_info">License Information</a>


Copyright (c) 2013-2016 Cisco and/or its affiliates.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
