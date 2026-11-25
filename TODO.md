# TODO

1. Inlay hints from total functions. A total function has the empty effect row.
   So it has no effects and it terminates. Run the function at the call site.
   Show the result as an inlay hint after the call.
   Limits: show a hint only when all arguments are static literals, the
   function is total, and the result type is showable. Skip the call when an
   argument is a runtime value, or when an argument needs an effectful
   computation.
