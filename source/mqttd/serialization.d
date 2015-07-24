﻿/**
 * 
 * /home/tomas/workspace/mqtt-d/source/factory.d
 * 
 * Author:
 * Tomáš Chaloupka <chalucha@gmail.com>
 * 
 * Copyright (c) 2015 Tomáš Chaloupka
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

debug import std.stdio;

auto serialize(R, T)(auto ref R output, ref T item) if (canSerializeTo!(R))
{
    return serializer(output).serialize(item);
}

auto serializer(R)(auto ref R output) if (canSerializeTo!(R))
{
    return Serializer!R(output);
}

/**
* Walk over all members of Mqtt packet, checks if member should be handled and calls defined callback for it
*/
private void processMembers(alias memberCallback, T)(ref T item) if (isMqttPacket!T)
{
    import std.typetuple;

    foreach(member; __traits(allMembers, T))
    {
        alias memberType = typeof(__traits(getMember, item, member));
        enum isMemberVariable = is(typeof(() {__traits(getMember, item, member) = __traits(getMember, item, member).init; }));
        //static if(is(memberType == struct)) pragma(msg, T, ".", member, " is struct");
        //static if(isDynamicArray!memberType && is(ElementType!memberType == struct)) pragma(msg, T, ".", member, " is struct array");

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

struct Serializer(R) if (canSerializeTo!(R))
{
    this(R output)
    {
        _output = output;
    }

    void put(ubyte val)
    {
        _output.put(val);
    }
    
    static if(__traits(hasMember, R, "data"))
    {
        @property auto data()
        {
            return _output.data();
        }
    }
    
    static if(__traits(hasMember, R, "clear"))
    {
        void clear()
        {
            _output.clear();
        }
    }

    /// Serialize given Mqtt packet
    void serialize(T)(ref T item) if (isMqttPacket!T)
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
        item.processMembers!((ref a) => write(a));
    }

private:
    R _output;

    void write(T)(T val) if (canWrite!T)
    {
        static if (is(T == FixedHeader)) // first to avoid implicit conversion to ubyte
        {
            put(val.flags);
            
            int tmp = val.length;
            do
            {
                byte digit = tmp % 128;
                tmp /= 128;
                if (tmp > 0) digit |= 0x80;
                put(digit);
            } while (tmp > 0);
        }
        else static if (is(T:ubyte))
        {
            put(val);
        }
        else static if (is(T:ushort))
        {
            put(cast(ubyte) (val >> 8));
            put(cast(ubyte) val);
        }
        else static if (is(T:string))
        {
            import std.string : representation;
            
            enforce(val.length <= 0xFF, "String too long: ", val);
            
            write((cast(ushort)val.length));
            foreach(b; val.representation) put(b);
        }
        else static if (isDynamicArray!T)
        {
            foreach(ret; val) write(ret);
        }
        else static if (is(T == Topic))
        {
            write(val.filter);
            write(val.qos);
        }
    }
}
