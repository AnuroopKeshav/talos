(module
  (func $fact (export "fact") (param i32) (result i32) (local i32)
    i32.const 1
    local.set 1
    loop
      local.get 0
      i32.eqz
      if
      else
        local.get 1
        local.get 0
        i32.mul
        local.set 1
        local.get 0
        i32.const 1
        i32.sub
        local.set 0
        br 1
      end
    end
    local.get 1))
