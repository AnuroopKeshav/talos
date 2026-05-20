(module
  (func $sum_to (export "sum_to") (param i32) (result i32) (local i32)
    loop
      local.get 0
      i32.eqz
      if
      else
        local.get 1
        local.get 0
        i32.add
        local.set 1
        local.get 0
        i32.const 1
        i32.sub
        local.set 0
        br 1
      end
    end
    local.get 1))
