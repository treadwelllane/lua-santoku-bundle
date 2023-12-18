# Now

- Use santoku-template for templating
- Replace copied lua_compat functions in bundle template
- lua_loadbuffer last argument is current set to an abosolute path. It should
  instead be set to a relative path or a single file name
- Refactor the single file abomination

- doesn't work with busybox xxd since it is missing the -n flag, which allows us
  to specify the name of the variable the compiled lua file is stored in
