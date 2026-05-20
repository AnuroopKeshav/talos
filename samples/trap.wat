(module
  (func $div_by_zero (export "div_by_zero") (result i32)
    i32.const 1
    i32.const 0
    i32.rem_u))
