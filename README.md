# Alternative Erlang crash dump parser


Features:

- tries to parse truncated process dumps.
- `crashdump_aparser:make_memory_map("<0.6.0>")` - reads process heap
  making mapping between heap address and offset in the crash dump.
- `crashdump_aparser:proc_details("<0.6.0>", 15)` - partial parsing (each list
  is limited by 15 elements).
- `crashdump_aparser:parse_limited({'#CDVLimitReached',"H790B5E00"}, 10)` -
  parses a list tail.
- `crashdump_aparser:calc_limited_length({'#CDVLimitReached',"H790B5E00"}, 100)` -
  calculates a list length.


# Usage example

```erlang
cd src/
erl


f().
c(skipinttab).
c(crashdump_aparser).
File = "erl_crash.dump".
spawn(fun() -> {ok,CdvServer} = crashdump_aparser:start_link() end).
crashdump_aparser:read_file(File). % cast
rp(crashdump_aparser:make_memory_map("<0.6.0>")).
rp(crashdump_aparser:proc_details("<0.6.0>", 15)).
```
