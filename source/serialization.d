﻿/**
 * 
 * /home/tomas/workspace/mqtt-d/source/factory.d
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
module mqttd.serialization;

import std.string : format;
import std.range;
import std.typecons;

import mqttd.messages;
import mqttd.traits;
import mqttd.ranges;

debug import std.stdio;

/**
* Walk over all members of Mqtt packet, checks if member should be handled and calls defined callback for it
*/
void processMembers(alias memberCallback, T)(ref T item) if (isMqttPacket!T)
{
    import std.typetuple;

    foreach(member; __traits(allMembers, T))
    {
        enum isMemberVariable = is(typeof(() {__traits(getMember, item, member) = __traits(getMember, item, member).init; }));

        static if(isMemberVariable)
        {
            auto include = true;
            foreach(attr; __traits(getAttributes, __traits(getMember, item, member)))
            {
                enum idx = staticIndexOf!(attr, __traits(getAttributes, __traits(getMember, item, member)));
                static if(isCondition!(typeof(attr)))
                {
                    //check condition
                    auto attribute = mixin(`__traits(getAttributes, T.` ~ member ~ `)`)[idx];
                    if(!attribute.cond(item))
                    {
                        include = false;
                        continue;
                    }
                }
            }

            if(include)
            {
                //debug writeln("processing ", member);
                memberCallback(__traits(getMember, item, member));
            }
        }
    }
}

/// Serialize given Mqtt packet
void serialize(W, T)(ref W wtr, ref T item) if (isMqttPacket!T && is(W == Writer!Out, Out))
{
    static assert(hasFixedHeader!T, format("'%s' packet has no required header field!", T.stringof));

    //set remaining packet length by checking packet conditions
    int len;
    item.processMembers!(a => len += a.itemLength);
    item.header.length = len;

    //check if is valid
    try item.validate();
    catch (Exception ex) 
        throw new PacketFormatException(format("'%s' packet is not valid: %s", T.stringof, ex.msg), ex);

    //write members to output writer
    item.processMembers!((ref a) => wtr.write(a));
}

T deserialize(T, R)(ref R rdr) if (isMqttPacket!T && is(R == Reader!In, In))
{
    import std.exception : enforce;

    static assert(hasFixedHeader!T, format("'%s' packet has no required header field!", T.stringof));

    T res;

    res.processMembers!((ref a) => a = rdr.read!(typeof(a)));

    // validate initialized packet
    try res.validate();
    catch (Exception ex) 
        throw new PacketFormatException(format("'%s' packet is not valid: %s", T.stringof, ex.msg), ex);

    return res;
}

/// Connect message tests
unittest
{
    import std.array;

    auto con = Connect();
    con.clientIdentifier = "testclient";
    con.flags.userName = true;
    con.userName = "user";

    auto buffer = appender!(ubyte[]);
    auto wr = writer(buffer);

    wr.serialize(con);

    assert(wr.data.length == 30);

    //debug writefln("%(%.02x %)", wr.data);
    assert(wr.data == cast(ubyte[])[
            0x10, //fixed header
            0x1c, // rest is 28
            0x00, 0x04, //length of MQTT text
            0x4d, 0x51, 0x54, 0x54, // MQTT
            0x04, //protocol level
            0x80, //just user name flag
            0x00, 0x00, //zero keepalive
            0x00, 0x0a, //length of client identifier
            0x74, 0x65, 0x73, 0x74, 0x63, 0x6c, 0x69, 0x65, 0x6e, 0x74, //testclient text
            0x00, 0x04, //username length
            0x75, 0x73, 0x65, 0x72 //user text
        ]);

    auto data = reader(buffer.data);

    auto con2 = deserialize!Connect(data);
    assert(con == con2);
}

unittest
{
    auto conack = ConnAck();

    auto buffer = appender!(ubyte[]);
    auto wr = writer(buffer);

    wr.serialize(conack);

    assert(wr.data.length == 4);

    //debug writefln("%(%.02x %)", wr.data);
    assert(wr.data == cast(ubyte[])[
            0x20, //fixed header
            0x02, //rest is 2
            0x00, //flags
            0x00  //return code
        ]);

    auto data = reader(buffer.data);

    auto conack2 = deserialize!ConnAck(data);

    // TODO: this for some reason fails..
//    writefln("%(%.02x %)", *(cast(byte[ConnAck.sizeof]*)(&conack)));
//    writefln("%(%.02x %)", *(cast(byte[ConnAck.sizeof]*)(&conack2)));
//    assert(conack == conack2);
    assert(conack.header == conack2.header);
    assert(conack.flags == conack2.flags);
    assert(conack.returnCode == conack2.returnCode);
    assert(conack.returnCode == ConnectReturnCode.ConnectionAccepted);

    conack2.flags = 0x01;
    conack2.returnCode = ConnectReturnCode.NotAuthorized;
    buffer.clear();

    wr.serialize(conack2);

    assert(wr.data.length == 4);
    assert(wr.data == cast(ubyte[])[
            0x20, //fixed header
            0x02, //rest is 2
            0x01, //flags
            0x05  //return code
        ]);
}

unittest
{
    auto pa = PubAck();
    
    auto buffer = appender!(ubyte[]);
    auto wr = writer(buffer);
    
    wr.serialize(pa);
    
    assert(wr.data.length == 4);
    
    //debug writefln("%(%.02x %)", wr.data);
    assert(wr.data == cast(ubyte[])[
            0x40, //fixed header
            0x02, //rest is 2
            0x00, 0x00  //packet id
        ]);
    
    auto data = reader(buffer.data);
    
    auto pa2 = deserialize!PubAck(data);
    
    assert(pa == pa2);
    
    pa2.packetId = 0xabcd;
    buffer.clear();
    
    wr.serialize(pa2);
    
    assert(wr.data.length == 4);
    assert(wr.data == cast(ubyte[])[
            0x40, //fixed header
            0x02, //rest is 2
            0xab, 0xcd  //packet id
        ]);
}
