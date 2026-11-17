Notes for AI sessions in LIB_RTS

- Read README.md and DESIGN.md first. The library must stay free of windows and IDE calls; drawing belongs in the demo or a game.
- Test with `python3 -I ~/projects/OXT-BEYOND/tests/oxt_headless.py tests/t_rts_library.txt tests/t_rts_demo.txt`. t_rts_demo.txt uses a copy in the session scratchpad (path at the top): change it to a fresh copy before running.
- Handlers that return a value are functions (RTS.NewGame, RTS.TabThrough, RTS.ClickAt); call them as F().
- In the demo, refer to controls with `of stack "RTS_Demo"`: `go card X of me` does not compile.
