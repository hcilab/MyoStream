# Introduction

A reusable, barebones tools for streaming EMG samples directly from the Myo Armband through the armband's Bluetooth Smart interface (aka Bluetooth Low Energy) for Processing, bypassing the need to use the MyoConnect software.

This tool assumes that you are using the dongle provided with the myo armband, which communicates with the armband using Bluetooth LE, but presents itself to your computer as a serial communication device. This tool does therefore not work as-is with with a generic Bluetooth device or dongle.

The project is extremely barebones, and is currently not appropriate to be used as a generic Bluetooth LE interface or library. I've only implemented the Bluetooth LE functionality that was required for my specific use-case. Similarly, this is not a generic library for interfacing the Myo armband.


# Background

The biggest hurdle in completing this project was learning how the Bluetooth communication occurred between the host computer and the armband. Trying to piece together the structure of the commands and responses was difficult because the information required to do so was scattered across many different sites, books, and projects. I'm including this background section to (hopefully) make the learning curve slightly less steep for those looking to do similar projects in the future.


## Bluetooth Low Energy (BLE)

Bluetooth Low Energy (also called Bluetooth LE, BLE, or Bluetooth Smart) is a protocol specification that was first defined in the Bluetooth v4.0 spec. Bluetooth LE is not simply a sub-set of Bluetooth, but is instead a totally separate protocol designed from the ground up with low power consumption in mind. A great introduction to Bluetooth LE can be found in the first 4 chapters of O'Reilly `Getting Started with Bluetooth Low Energy`. Pay specific attention to chapter 4, the GATT protocol, as this covers the majority of interactions that will be conducted with a device through BLE.


### Generic Attribute (GATT) protocol

Once a connection with a peripheral device is established (through a protocol known as GAP, discussed in chapter 3 of the book mentioned above), the client (i.e., computer, cell-phone) and server (i.e., armband, heart-rate monitor) communicate using a protocol known as GATT. Conceptually, the server is essentially a database which can be queried for data (which is known as an attribute) using either a UUID or a handle.

  - **UUIDs** come in 2 flavors. The most commonly used pieces of data (e.g., heart-rate, blood-pressure) have been assigned standardized UUIDs by the Bluetooth specification, meaning that the UUID of these pieces of data will be consistent across all compliant peripheral devices. This allows an application working with a common metric, say heart-rate, to query the peripheral directly using the standardized UUID, and allows the same code to work across many different peripheral devices. Less commonly used pieces of data are simply assigned a UUID which is unique within the device.

  - **Handles**, on the other hand, can be loosely thought of as a memory address. Each attribute is stored at a specific and unique handle. However, the analogy stops there, because the size of individual attributes varies across different handles, and there is also no guarantee that handles IDs will be contiguous.

In the most basic use-case, the client queries the server using either a UUID or a handle, and subsequently receives a response containing the data of interest. However, the server can also be configured to push certain pieces of data asynchronously to the client through mechanism called notifications and indications

  - **Notification**: The server pushes a message to the client each time the data is modified. The server does not require any confirmation that the message was delivered successfully. *Think UDP*

  - **Indication**: The server pushes a message to the client when the data is modified, but does not push subsequent messages until confirmation of receipt is received from the client. *Think TCP*


#### Characteristics, Attributes, Values and Descriptors

Aspect of GATT that I found confusing at first were the (seemingly) ambiguous use of the terms 'characteristic' and 'attribute', and the structure and indirection found in the GATT table.

  - **Attribute**: Every entry/line in the GATT table is is referred to as an attribute. Some of these attributes also happen to be characteristics, characteristic values, and characteristic descriptors.

    - **Characteristic**: A characteristic is essentially a 'label' for a piece of data stored in the GATT table. The characteristic stores the UUID (identifying which type of data is stored within the characteristic), access permissions, and the handle within which the value of this characteristic can be found. In a rough analogy comparing characteristics to variables in a programming language, the characteristic is the *variable name*.

    - **Value**: This is where the actual data is stored. We know how to interpret the data because the corresponding characteristic stored a copy of the value's handle (essentially a pointer to the value). In the variable analogy, the value is the *variables value*

    - **Descriptor**: A descriptor is an optional attribute (some characteristics have them, some don't) that stores additional information about the characteristic. The most useful descriptor I've used in this project is the Client Characteristic Configuration Descriptor (or CCCD). This descriptor is 2 bytes in length, and stores boolean flags specifying whether the server should provide notifications/indications of the characteristic to the client.


#### Details of the GATT protocol

OReilly's `Getting Started With Bluetooth Low Energy` provided a great conceptual understanding of how the GATT protocol works, however, I had difficulty finding documentation for the structure and opcodes of the specific GATT commands. The `bglib` project provides a great overview of this information:

  https://github.com/jrowberg/bglib


In general, all GATT messages start with a 4-byte header and are structured as follows:

'''
  <type> <payloadSize> <opcodeClass> <opcodeCommand> <payloadByte1> <payloadByte2> ...
'''

  - **type**: For Bluetooth, either 0x00 (indicating that this is a command), or 0x80 (indicating that this is an asynchronous event, such as a notification)

  - **payloadSize**: The length of the payload. The entire message will be (4 + payloadSize) bytes.

  - **opcodeClass** / **opcodeCommand**: These two bytes specify which GATT command should be issued. For more details, see the `bglib` project.


Many of the GATT commands use the first few bytes of the payload to hold additional information, such as the connection ID and the handle/UUID to read or write.


### Myo armband-specific protocol

Commands for controlling the behavior of the armband are encoded in the payload of GATT-write commands, and a written to a specific attribute of the GATT table. To send a command to the Myo armband, use the 'write attribute by handle' GATT command to write a message to the 0x0019 handle. The payload of this message should contain the Myo-specific command. The structure and opcodes for Myo-specific commands can be found in the publicly available header-file, found here:

 https://github.com/thalmiclabs/myo-bluetooth/blob/master/myohw.h


#### Myo EMG

Here are links to a few articles that clearly explain the steps required to stream EMG data from the Myo armband:

  http://developerblog.myo.com/myo-bluetooth-spec-released/

  http://developerblog.myo.com/myocraft-emg-in-the-bluetooth-protocol/


# Debugging Tools

During this project, I learned to use a few Linux command line debugging tools that turned out to be incredibly useful for prototyping commands and visualizing the GATT table.

  - **hcitool**: This tool can be used to find the MAC address of a nearby BLE device. Issue the command: `hcitool -i hciX lescan`, replacing the X with the appropriate Bluetooth interface number.

  - **gatttool**: This tool can be used to connect with a BLE device in an interactive session. Within this session, you can issue commands and query the GATT table. Issue the command: `gatttool -b <mac-address> -I` to start an interactive session.


# Reference Material

Books:

  - OReilly Getting Started with Bluetooth Low Energy

git projects:

  - bglib: https://github.com/jrowberg/bglib

  - myo-raw: https://github.com/dzhu/myo-raw

Myo-specific information:

  - Blog Posts

    - http://developerblog.myo.com/myo-bluetooth-spec-released/

    - http://developerblog.myo.com/myocraft-emg-in-the-bluetooth-protocol/

  - Technical Specifications

    - https://github.com/thalmiclabs/myo-bluetooth/blob/master/myohw.h

