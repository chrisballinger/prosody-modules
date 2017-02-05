While the bandwidth usage of XMPP isn't that much, compressing the data
sent to/from your server can give significant benefits to those on slow
connections, such as dial-up or mobile networks. Prosody supports
compression for client-to-server (if your client supports it) and
server-to-server streams using the mod\_compression plugin.

# Details

mod\_compression implements [XEP-0138], and supports the zlib compression
algorithm.

## Dependencies

The XMPP protocol specifies that all clients and servers supporting
compression must support the "zlib" compression method, and this is what
Prosody uses. However you will need to install zlib support for Lua on
your system. There are different ways of doing this depending on your
system. If in doubt whether it is installed correctly, the command
`lua-lzlib` in a console should open a Lua prompt with no errors.

For more information on obtaining lua-zlib for your platform, see the
[dependencies page][doc:depends].

# Usage

``` lua
modules_enabled = {
    -- Other modules
    "compression"; -- Enable mod_compression
}
```

## Configuration

The compression level can be set using the `compression_level` option
which can be a number from 1 to 9. Higher compression levels will use
more resources but less bandwidth.

## Example

``` lua
modules_enabled = {
    -- Other modules
    "compression"; -- Enable mod_compression
}
 
compression_level = 5
```
