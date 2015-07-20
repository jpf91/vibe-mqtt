﻿/**
 * 
 * /home/tomas/workspace/mqtt-d/source/message.d
 * 
 * Author:
 * Tomáš Chaloupka <chalucha@gmail.com>
 * 
 * Copyright (c) 2015 ${CopyrightHolder}
 * 
 * Boost Software License 1.0 (BSL-1.0)
 * 
 * Permission is hereby granted, free of charge, to any person or organization obtaining a copy
 * of the software and accompanying documentation covered by this license (the "Software") to use,
 * reproduce, display, distribute, execute, and transmit the Software, and to prepare derivative
 * works of the Software, and to permit third-parties to whom the Software is furnished to do so,
 * all subject to the following:
 * 
 * The copyright notices in the Software and this entire statement, including the above license
 * grant, this restriction and the following disclaimer, must be included in all copies of the Software,
 * in whole or in part, and all derivative works of the Software, unless such copies or derivative works
 * are solely in the form of machine-executable object code generated by a source language processor.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
 * INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
 * PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR ANYONE
 * DISTRIBUTING THE SOFTWARE BE LIABLE FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */
module mqttd.messages;

import std.range;
import std.exception : enforce;
import std.traits : isIntegral;

import mqttd.traits;

enum ubyte MQTT_PROTOCOL_LEVEL_3_1_1 = 0x04;
enum string MQTT_PROTOCOL_NAME = "MQTT";

/**
 * MQTT Control Packet type
 * 
 * http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Table_2.1_-
 */
enum PacketType : ubyte
{
    /// Forbidden - Reserved
    RESERVED1   = 0,
    /// Client -> Server - Client request to connect to Server
    CONNECT     = 1,
    /// Server -> Client - Connect acknowledgment
    CONNACK     = 2,
    /// Publish message
    PUBLISH     = 3,
    /// Publish acknowledgment
    PUBACK      = 4,
    /// Publish received (assured delivery part 1)
    PUBREC      = 5,
    /// Publish release (assured delivery part 2)
    PUBREL      = 6,
    /// Publish complete (assured delivery part 3)
    PUBCOMP     = 7,
    /// Client -> Server - Client subscribe request
    SUBSCRIBE   = 8,
    /// Server -> Client - Subscribe acknowledgment
    SUBACK      = 9,
    /// Client -> Server - Unsubscribe request
    UNSUBSCRIBE = 10,
    /// Server -> Client - Unsubscribe acknowledgment
    UNSUBACK    = 11,
    /// Client -> Server - PING request
    PINGREQ     = 12,
    /// Server -> Client - PING response
    PINGRESP    = 13,
    /// Client -> Server - Client is disconnecting
    DISCONNECT  = 14,
    /// Forbidden - Reserved
    RESERVED2   = 15
}

/**
 * Indicates the level of assurance for delivery of an Application Message
 * http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Table_3.11_-
 */
enum QoSLevel : ubyte
{
    /// At most once delivery
    AtMostOnce = 0x0,
    /// At least once delivery
    AtLeastOnce = 0x1,
    /// Exactly once delivery
    ExactlyOnce = 0x2,
    /// Reserved – must not be used
    Reserved = 0x3
}

struct Condition
{
    string cond;
}

/**
 * Exception thrown when package format is somehow malformed
 */
class PacketFormatException : Exception
{
    this(string msg = null, Throwable next = null)
    {
        super(msg, next);
    }
}

/**
 * Each MQTT Control Packet contains a fixed header.
 * 
 * http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html#_Figure_2.2_-
 */
struct FixedHeader
{
    /// Represented as a 4-bit unsigned value
    PacketType type;

    /// Duplicate delivery of a PUBLISH Control Packet
    bool dup;
    
    /// Quality Of Service for a message
    QoSLevel qos;
    
    /// PUBLISH Retain flag 
    bool retain;

    /**
     * The Remaining Length is the number of bytes remaining within the current packet, 
     * including data in the variable header and the payload. 
     * The Remaining Length does not include the bytes used to encode the Remaining Length.
     */
    uint length;

    @safe @nogc
    @property ubyte flags() const pure nothrow
    {
        return cast(ubyte)((type << 4) | (dup ? 0x08 : 0x00) | (retain ? 0x01 : 0x00) | (qos << 1));
    }

    @safe @nogc
    @property void flags(ubyte value) pure nothrow
    {
        type = cast(PacketType)(value >> 4);
        dup = (value & 0x08) == 0x08;
        retain = (value & 0x01) == 0x01;
        qos = cast(QoSLevel)((value >> 1) & 0x03);
    }

    alias flags this;

    this(PacketType type, bool dup, QoSLevel qos, bool retain, int length = 0)
    {
        this.type = type;
        this.dup = dup;
        this.retain = retain;
        this.qos = qos;
        this.length = length;
    }

    this(T)(PacketType type, T flags, int length = 0) if(isIntegral!T)
    {
        this.flags = cast(ubyte)flags;
        this.type = type;
        this.length = length;
    }

    this(T)(T value) if(isIntegral!T)
    {
        this.flags = cast(ubyte)value;
    }
}

/**
 * The Connect Flags byte contains a number of parameters specifying the behavior of the MQTT connection.
 * It also indicates the presence or absence of fields in the payload.
 */
struct ConnectFlags
{
    /**
     * If the User Name Flag is set to 0, a user name MUST NOT be present in the payload.
     * If the User Name Flag is set to 1, a user name MUST be present in the payload.
     */
    bool userName;

    /**
     * If the Password Flag is set to 0, a password MUST NOT be present in the payload.
     * If the Password Flag is set to 1, a password MUST be present in the payload.
     * If the User Name Flag is set to 0, the Password Flag MUST be set to 0.
     */
    bool password;

    /**
     * This bit specifies if the Will Message is to be Retained when it is published.
     * 
     * If the Will Flag is set to 0, then the Will Retain Flag MUST be set to 0.
     * If the Will Flag is set to 1:
     *      If Will Retain is set to 0, the Server MUST publish the Will Message as a non-retained message.
     *      If Will Retain is set to 1, the Server MUST publish the Will Message as a retained message
     */
    bool willRetain;

    /**
     * Specify the QoS level to be used when publishing the Will Message.
     * 
     * If the Will Flag is set to 0, then the Will QoS MUST be set to 0 (0x00).
     * If the Will Flag is set to 1, the value of Will QoS can be 0 (0x00), 1 (0x01), or 2 (0x02).
     * It MUST NOT be 3 (0x03)
     */
    QoSLevel willQoS;

    /**
     * If the Will Flag is set to 1 this indicates that, if the Connect request is accepted, a Will Message MUST 
     * be stored on the Server and associated with the Network Connection. The Will Message MUST be published 
     * when the Network Connection is subsequently closed unless the Will Message has been deleted by the Server 
     * on receipt of a DISCONNECT Packet.
     * 
     * Situations in which the Will Message is published include, but are not limited to:
     *      An I/O error or network failure detected by the Server.
     *      The Client fails to communicate within the Keep Alive time.
     *      The Client closes the Network Connection without first sending a DISCONNECT Packet.
     *      The Server closes the Network Connection because of a protocol error.
     * 
     * If the Will Flag is set to 1, the Will QoS and Will Retain fields in the Connect Flags will be used by 
     * the Server, and the Will Topic and Will Message fields MUST be present in the payload.
     * 
     * The Will Message MUST be removed from the stored Session state in the Server once it has been published 
     * or the Server has received a DISCONNECT packet from the Client.
     * 
     * If the Will Flag is set to 0 the Will QoS and Will Retain fields in the Connect Flags MUST be set to zero 
     * and the Will Topic and Will Message fields MUST NOT be present in the payload.
     * 
     * If the Will Flag is set to 0, a Will Message MUST NOT be published when this Network Connection ends
     */
    bool will;

    /**
     * This bit specifies the handling of the Session state. 
     * The Client and Server can store Session state to enable reliable messaging to continue across a sequence 
     * of Network Connections. This bit is used to control the lifetime of the Session state. 
     * 
     * If CleanSession is set to 0, the Server MUST resume communications with the Client based on state from 
     * the current Session (as identified by the Client identifier). 
     * If there is no Session associated with the Client identifier the Server MUST create a new Session. 
     * The Client and Server MUST store the Session after the Client and Server are disconnected.
     * After the disconnection of a Session that had CleanSession set to 0, the Server MUST store 
     * further QoS 1 and QoS 2 messages that match any subscriptions that the client had at the time of disconnection 
     * as part of the Session state.
     * It MAY also store QoS 0 messages that meet the same criteria.
     * 
     * If CleanSession is set to 1, the Client and Server MUST discard any previous Session and start a new one.
     * This Session lasts as long as the Network Connection. State data associated with this Session MUST NOT be reused
     * in any subsequent Session.
     * 
     * The Session state in the Client consists of:
     *      QoS 1 and QoS 2 messages which have been sent to the Server, but have not been completely acknowledged.
     *      QoS 2 messages which have been received from the Server, but have not been completely acknowledged. 
     * 
     * To ensure consistent state in the event of a failure, the Client should repeat its attempts to connect with 
     * CleanSession set to 1, until it connects successfully.
     * 
     * Typically, a Client will always connect using CleanSession set to 0 or CleanSession set to 1 and not swap 
     * between the two values. The choice will depend on the application. A Client using CleanSession set to 1 will 
     * not receive old Application Messages and has to subscribe afresh to any topics that it is interested in each 
     * time it connects. A Client using CleanSession set to 0 will receive all QoS 1 or QoS 2 messages that were 
     * published while it was disconnected. Hence, to ensure that you do not lose messages while disconnected, 
     * use QoS 1 or QoS 2 with CleanSession set to 0.
     * 
     * When a Client connects with CleanSession set to 0, it is requesting that the Server maintain its MQTT session 
     * state after it disconnects. Clients should only connect with CleanSession set to 0, if they intend to reconnect 
     * to the Server at some later point in time. When a Client has determined that it has no further use for 
     * the session it should do a final connect with CleanSession set to 1 and then disconnect.
     */
    bool cleanSession;

    @safe @nogc
    @property ubyte flags() const pure nothrow
    {
        return cast(ubyte)(
            (userName ? 0x80 : 0x00) | 
            (password ? 0x40 : 0x00) | 
            (willRetain ? 0x20 : 0x00) |
            (willQoS << 3) |
            (will ? 0x04 : 0x00) |
            (cleanSession ? 0x02 : 0x00)
            );
    }

    @safe @nogc
    @property void flags(ubyte value) pure nothrow
    {
        userName = (value & 0x80) == 0x80;
        password = (value & 0x40) == 0x40;
        willRetain = (value & 0x20) == 0x20;
        willQoS = cast(QoSLevel)((value >> 3) & 0x03);
        will = (value & 0x04) == 0x04;
        cleanSession = (value & 0x02) == 0x02;
    }
    
    this(bool userName, bool password, bool willRetain, QoSLevel willQoS, bool will, bool cleanSession)
    {
        this.userName = userName;
        this.password = password;
        this.willRetain = willRetain;
        this.willQoS = willQoS;
        this.will = will;
        this.cleanSession = cleanSession;
    }
    
    this(T)(T value) if(isIntegral!T)
    {
        this.flags = cast(ubyte)value;
    }
    
    alias flags this;
}

/// Computes and sets remaining length to the package header field
@safe @nogc
void setRemainingLength(T)(auto ref T msg) pure nothrow
{
    uint len;
    static if (is(T == Connect))
    {
        len = msg.protocolName.itemLength + msg.protocolLevel.itemLength + msg.connectFlags.itemLength + 
            msg.keepAlive.itemLength + msg.clientIdentifier.itemLength;
    
        if (msg.connectFlags.will) len += msg.willTopic.itemLength + msg.willMessage.itemLength;
        if (msg.connectFlags.userName)
        {
            len += msg.userName.itemLength;
            if (msg.connectFlags.password) len += msg.password.itemLength;
        }
    }
    else assert(0, "Not implemented setRemainingLength for " ~ T.stringof);
    
    msg.header.length = len;
}

/// Gets required buffer size to encode into
@safe @nogc
uint itemLength(T)(auto ref in T item) pure nothrow
{
    static if (is(T == ubyte)) return 1;
    else static if (is(T == ushort)) return 2;
    else static if (is(T == string)) return cast(uint)(2 + item.length);
    else static if (is(T == ConnectFlags)) return 1;
    else assert(0, "Not implemented itemLength for " ~ T.stringof);
}

@safe
void checkPacket(T)(auto ref in T packet) pure
{
    import std.string : format;

    static if (__traits(hasMember, T, "header"))
    {
        void checkHeader(ubyte value, ubyte mask = 0xFF)
        {
            enforce(packet.header == (value & mask), "Wrong header");
        }
    }

    static if (__traits(hasMember, T, "clientIdentifier"))
    {
        enforce(packet.clientIdentifier.length > 0 && packet.clientIdentifier.length < 24,
            "Client Identifier SHOULD be 1 to 23 characters long");
    }

    static if (is(T == ConnectFlags))
    {
        enforce(packet.will || (packet.willQoS == QoSLevel.AtMostOnce && !packet.willRetain), 
            "WillQoS and Will Retain MUST be 0 if Will flag is not set");
        enforce(packet.userName || !packet.password, "Password MUST be set to 0 if User flag is 0");
    }
    else static if (is(T == Connect))
    {
        checkHeader(0x10);
        enforce(packet.header.length != 0, "Length must be set!");
        enforce(packet.protocolName == MQTT_PROTOCOL_NAME, 
            format("Wrong protocol name '%s', must be '%s'", packet.protocolName, MQTT_PROTOCOL_NAME));
        enforce(packet.protocolLevel == MQTT_PROTOCOL_LEVEL_3_1_1, 
            format("Unsuported protocol level '%d', must be '%d' (v3.1.1)", packet.protocolLevel, MQTT_PROTOCOL_LEVEL_3_1_1));
        packet.connectFlags.checkPacket();
        enforce(!packet.connectFlags.userName || packet.userName.length > 0, "Username not set");
    }
}

//TODO: Replace with Writer and serialize
/// Write item bytes to delegate sink
void toBytes(T)(auto ref in T item, scope void delegate(ubyte) sink)
{
    //write header
    static if (__traits(hasMember, T, "header")) item.header.toBytes(sink);
    static if (is(T == ubyte))
    {
        sink(item);
    }
    else static if (is(T == ushort))
    {
        sink(cast(ubyte) (item >> 8));
        sink(cast(ubyte) item);
    }
    else static if (is(T == string))
    {
        import std.string : representation;
        
        enforce(item.length <= 0xFF, "String too long: ", item);
        
        (cast(ushort)item.length).toBytes(sink);
        foreach(b; item.representation)
        {
            sink(b);
        }
    }
    else static if (is(T == FixedHeader))
    {
        sink(item.flags);
        
        int tmp = item.length;
        do
        {
            byte digit = tmp % 128;
            tmp /= 128;
            if (tmp > 0) digit |= 0x80;
            sink(digit);
        } while (tmp > 0);
    }
    else static if (is(T == ConnectFlags))
    {
        sink(item.flags);
    }
    else static if (is(T == Connect))
    {
        item.protocolName.toBytes(sink);
        item.protocolLevel.toBytes(sink);
        item.connectFlags.toBytes(sink);
        item.keepAlive.toBytes(sink);
        item.clientIdentifier.toBytes(sink);

        if (item.connectFlags.will)
        {
            item.willTopic.toBytes(sink);
            item.willMessage.toBytes(sink);
        }
        if (item.connectFlags.userName)
        {
            item.userName.toBytes(sink);
            if (item.connectFlags.password) item.password.toBytes(sink);
        }
    }
    else assert(0, "Not implemented toBytes for " ~ T.stringof);
}

/**
 * After a Network Connection is established by a Client to a Server, 
 * the first Packet sent from the Client to the Server MUST be a CONNECT Packet.
 * 
 * A Client can only send the CONNECT Packet once over a Network Connection. 
 * The Server MUST process a second CONNECT Packet sent from a Client as a protocol violation and disconnect the Client.
 * 
 * The payload contains one or more encoded fields.
 * They specify a unique Client identifier for the Client, a Will topic, Will Message, User Name and Password.
 * All but the Client identifier are optional and their presence is determined based on flags in the variable header.
 */
struct Connect
{
    FixedHeader header;

    /// The Protocol Name is a UTF-8 encoded string that represents the protocol name “MQTT”
    string protocolName;

    /**
     * The 8 bit unsigned value that represents the revision level of the protocol used by the Client.
     * The value of the Protocol Level field for the version 3.1.1 of the protocol is 4 (0x04).
     */
    ubyte protocolLevel = 4;

    /**
     * The Connect Flags byte contains a number of parameters specifying the behavior of the MQTT connection.
     * It also indicates the presence or absence of fields in the payload.
     */
    ConnectFlags connectFlags;

    /**
     * The Keep Alive is a time interval measured in seconds. Expressed as a 16-bit word, it is the maximum time 
     * interval that is permitted to elapse between the point at which the Client finishes transmitting one Control 
     * Packet and the point it starts sending the next. It is the responsibility of the Client to ensure that the 
     * interval between Control Packets being sent does not exceed the Keep Alive value. 
     * In the absence of sending any other Control Packets, the Client MUST send a PINGREQ Packet.
     * 
     * The Client can send PINGREQ at any time, irrespective of the Keep Alive value, and use the PINGRESP to determine 
     * that the network and the Server are working.
     * 
     * If the Keep Alive value is non-zero and the Server does not receive a Control Packet from the Client within 
     * one and a half times the Keep Alive time period, it MUST disconnect the Network Connection to the Client as if 
     * the network had failed.
     * 
     * If a Client does not receive a PINGRESP Packet within a reasonable amount of time after it has sent a PINGREQ, 
     * it SHOULD close the Network Connection to the Server.
     * 
     * A Keep Alive value of zero (0) has the effect of turning off the keep alive mechanism. 
     * This means that, in this case, the Server is not required to disconnect the Client on the grounds of inactivity.
     * Note that a Server is permitted to disconnect a Client that it determines to be inactive or non-responsive 
     * at any time, regardless of the Keep Alive value provided by that Client.
     * 
     * The actual value of the Keep Alive is application specific; typically this is a few minutes. 
     * The maximum value is 18 hours 12 minutes and 15 seconds. 
     */
    ushort keepAlive;

    /// Client Identifier
    string clientIdentifier;

    /// Will Topic
    @Condition("connectFlags.will")
    string willTopic;

    /// Will Message
    string willMessage;

    /// User Name
    string userName;

    /// Password
    string password;

    static Connect opCall()
    {
        Connect res;
        res.header = 0x10;
        res.protocolName = MQTT_PROTOCOL_NAME;
        res.protocolLevel = MQTT_PROTOCOL_LEVEL_3_1_1;

        return res;
    }
}

struct ConnAck
{
    FixedHeader header;
}

struct Publish
{
    FixedHeader header;
    ushort packetId; // if QoS > 0
}

struct PubAck
{
    FixedHeader header;
    ushort packetId;
}

struct PubRec
{
    FixedHeader header;
    ushort packetId;
}

struct PubRel
{
    FixedHeader header;
    ushort packetId;
}

struct PubComp
{
    FixedHeader header;
    ushort packetId;
}

struct Subscribe
{
    FixedHeader header;
    ushort packetId;
}

struct SubAck
{
    FixedHeader header;
    ushort packetId;
}

struct Unsubscribe
{
    FixedHeader header;
    ushort packetId;
}

struct UnsubAck
{
    FixedHeader header;
    ushort packetId;
}

struct PingReq
{
    FixedHeader header;
}

struct PingResp
{
    FixedHeader header;
}

struct Disconnect
{
    FixedHeader header;
}

