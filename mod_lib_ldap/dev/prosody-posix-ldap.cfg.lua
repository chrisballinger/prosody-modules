-- Use Include 'prosody-posix-ldap.cfg.lua' from prosody.cfg.lua to include this file
authentication = 'ldap2' -- Indicate that we want to use LDAP for authentication
storage        = 'ldap'  -- Indicate that we want to use LDAP for roster/vcard storage

ldap = {
    hostname      = 'localhost',                    -- LDAP server location
    bind_dn       = 'cn=Manager,dc=example,dc=com', -- Bind DN for LDAP authentication (optional if anonymous bind is supported)
    bind_password = 'prosody',                      -- Bind password (optional if anonymous bind is supported)

    user = {
      basedn        = 'ou=Users,dc=example,dc=com',                  -- The base DN where user records can be found
      filter        = '(&(objectClass=posixAccount)(!(uid=seven)))', -- Filter expression to find user records under basedn
      usernamefield = 'uid',                                         -- The field that contains the user's ID (this will be the username portion of the JID)
      namefield     = 'cn',                                          -- The field that contains the user's full name (this will be the alias found in the roster)
    },

    groups = {
      basedn      = 'ou=Groups,dc=example,dc=com', -- The base DN where group records can be found
      memberfield = 'memberUid',                   -- The field that contains user ID records for this group (each member must have a corresponding entry under the user basedn with the same value in usernamefield)
      namefield   = 'cn',                          -- The field that contains the group's name (used for matching groups in LDAP to group definitions below)

      {
        name  = 'everyone', -- The group name that will be seen in users' rosters
        cn    = 'Everyone', -- This field's key *must* match ldap.groups.namefield! It's the name of the LDAP group this definition represents
        admin = false,      -- (Optional) A boolean flag that indicates whether members of this group should be considered administrators.
      },
      {
        name  = 'admin',
        cn    = 'Admin',
        admin = true,
      },
    },

    vcard_format = {
      displayname = 'cn', -- Consult the vCard configuration section in the README
      nickname    = 'uid',
      photo       = {
        type   = 'image/jpeg',
        binval = 'jpegPhoto',
      },
      telephone = {
        work = {
          voice = true,
          number = 'telephoneNumber',
        },
      },
    },
}
