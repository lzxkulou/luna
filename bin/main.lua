
print("hello !");

function test()
    print("enter test");

    local a, b = get_fucker();

    print(a.add(1, 2));
    print(b.add(10, 20));

    local c = same_fucker(a);
    print(a.add(100, 200));

    print("leave test");
end

test();

print("ms: "..get_time_ms());
print("ms: "..get_time_ms());

collectgarbage();

print("exit main.lua");
