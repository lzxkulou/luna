# 关于`luna`

## 这是个什么东西?

luna早期是一个lua的C++绑定库,现在是一个基于lua分布式服务器框架.当然,其中的C++绑定库还是可以单独拿出去使用.
主要特性:

- 方便的搭建任意拓扑结构集群.
- 方便的在集群进程间进行RPC调用.
- 方便的实现主要的集中消息转发方式如: 点对点,哈希转发,随机转发,广播,主从备份.
- 方便的进行lua与C++交互.
- 方便的使用脚本热加载,以实现高效开发&运维.

目前,这只是一个基础框架,只实现了最为精简的模块.
设计时,将尽可能方便使用者在此基础上修改/增/删模块.

注意本实现是基于多进程的,并且在远程调用(RPC)中也没返回值.
多进程设计主要出于两个原因:
- 容灾性,设计希望集群中任何服务都不会因为单个进程宕机而终止.
- 扩展性,希望实际运维时,能通过增减机器和进程而灵活的实现扩容缩容.

RPC为什么没有实现返回值呢?
这主要是为了简化设计减少失误,返回值完全可以用对端回调的RPC来实现.  
如果一定要把异步过程写得像同步过程一样,那不可避免的要引入协程来实现.  
在大规模项目中,这种写法容易让新手埋下错误,如协程栈上对象失效等问题.  
在本实现中,倾向于***如果事情是异步的,那就让它显然是异步的***.  

## 环境

luna同时支持Windows, Linux, macOS三平台,但是编译器必须支持C++14.  
我的开发环境如下(目前只支持64位,32位未经测试):

- Windows: Visual studio 2015
- macOS: Apple (GCC) LLVM 7.0.0
- Linux: GCC 5.3

## 文件沙盒及文件热加载

在luna中,用户主要通过全局的import函数加载lua文件.
- import为每个文件创建了一个沙盒环境,这使得各个文件中的变量名不会冲突.
- 在需要的地方,用户还可以继续使用require.
- 多次import同一个文件,实际上只会加重一次,import返回的是文件的环境表.
- 通过import加载的文件会定期的检查文件时间戳,如发生修改,则会自动热加载.

## 启停控制

#### 启动
程序启动后,默认会调用全局函数'luna\_entry':
```lua
function luna_entry(entry_file)
    --在这里import命令行指定的entry_file
    --然后循环调用entry_file中的on_loop函数,并定期(3秒)检查文件热加载
    --on_loop函数内部应该自己处理sleep之类的,以免CPU占用过高
end
```

#### 停止
收到信号时,会调用全局函数'on\_quit\_signal',默认会在其中设置退出标志'luna\_quit\_flag'.  
主循环在检查到'luna\_quit\_flag'标志时即退出.   
当然,用户可以定义自己的'on\_quit\_signal'函数.  

## C++导出函数

当函数的参数以及返回值是***基本类型***或者是***已导出类***时,可以直接用`lua_register_function`导出:

``` c++
int func_a(const char* a, int b);
int func_b(my_export_class_t* a, int b);
some_export_class* func_c(float x);

lua_register_function(L, func_a);
lua_register_function(L, func_b);
lua_register_function(L, func_c);
```

当然,你也可以导出lua标准的C函数.

## 导出类

首先需要在你得类声明中插入导出声明:

``` c++
class my_class final
{
	// ... other code ...
	int func_a(const char* a, int b);
	int func_b(some_class_t* a, int b);
    char m_name[32];
public:
    // 插入导出声明:
	DECLARE_LUA_CLASS(my_class);
};
```

在cpp中增加导出表的实现:

``` c++
EXPORT_CLASS_BEGIN(my_class)
EXPORT_LUA_FUNCTION(func_a)
EXPORT_LUA_FUNCTION(func_b)
EXPORT_LUA_STRING(m_name)
EXPORT_CLASS_END()
```

可以用带`_AS`的导出宏指定导出的名字,用带`_R`的宏指定导出为只读变量.
比如: `EXPORT_LUA_STRING_AS(m_name, Name)`

## 关于导出类(对象)的注意点

### 目前通过静态断言作了限制: 只能导出声明为final的类

这是为了避免无意间在父类和子类做出错误的指针转换
如果需要父类子类同时导出且保证不会出现这种错误,可以自行去掉这个断言

### 关于C++导出对象的生存期问题

注意,对象一旦被push进入lua,那么C++层面就不能随便删除它了.
绑定到lua中的C++对象,将会在lua影子对象gc时,自动delete.
如果这个对象在gc时不能调用delete,请在对象中实现gc方法: void gc();
这时gc将调用该函数,而不会直接delete对象.


## lua中访问导出对象

lua代码中直接访问导出对象的成员/方法即可.

``` lua
local obj = get_obj_from_cpp();
obj.func("abc", 123);
obj.name = "new name";
```

另外,C\+\+对象导出到lua中是通过一个table来实现的,可以称之为影子对象.
不但可以在lua中访问C\+\+对象成员,还可以有下面这些常见用法:

- 重载(覆盖)对象上的C\+\+导出方法.
- 在影子对象上增加额外的成员变量和方法.
- 在C\+\+中调用lua中为对象增加的方法,参见`lua_call_object_function`.

## C\+\+中调用lua函数

目前提供了两种支持:

- C++调用全局函数
- C++调用全局table中的函数
- C++调用导出对象上附加的函数.

下面以调用全局table中的函数为例:

``` lua
function s2s.some_func(a, b)
  	return a + b, a - b;
end
```

上面的lua函数返回两个值,那么,可以在C++中这样调用:

```cpp
int x, y;
lua_guard g(L);
// x,y用于接收返回值
lua_call_table_function(L, "s2s", "test.lua", "some_func", std::tie(x, y), 11, 2);
```

注意上面这里的lua_guard,所有从C++调用Lua的地方,都需要通过它来做栈保护.
请注意它的生存期,它实际上做的事情是:

1. 在构造是调用`lua_gettop`保存栈.
2. 析构时调用`lua_settop`恢复栈.


如果lua函数无返回值,也无参数,那么会比较简单:

```cpp
lua_guard g(L);
lua_call_table_function(L, "s2s", "some_func");
```

下面是lua函数无返回, 有a,b,c三个参数的情况:

```cpp
lua_guard g(L);
int a;
char* b;
std::string c;
lua_call_table_function(L, "s2s", "some_func", std::tie(), a, b, c);
```


## 网络
首先,你需要一个socket_mgr对象:

```lua
socket_mgr = create_socket_mgr(最大句柄数);
--用户需要在主循环中调用wait函数,比如:
--其参数为最大阻塞时长(实际是传给epoll_wait之类函数),单位ms.
socket_mgr.wait(50);
```

监听端口:

```lua
--注意保持listener的生存期,一旦被gc,则端口就自动关了
listener = mgr.listen("127.0.0.1", 8080);
```

发起连接:

```lua
--注意保持stream对象生存期,被gc的话,连接会自动关闭
--连接都是异步进行的,一直要stream上面触发'on_connected'事件后,连接才可用
--发生任何错误时,stream会触发'on_error'事件.
stream = mgr.connect("127.0.0.1", 8080);
```

向对端发送消息:

```lua
--TODO: 将来还可能在socket_mgr上增加广播方法
stream.call("on_login", acc, password);
```

响应消息:

```lua
stream.on_error = function (err)
    --发生任何错误时触发
end

stream.on_recv = function (msg, ...)
    --收到对端消息时触发.
    --通常这里是以...为参数调用msg对应的函数过程.
end
```

主动断开:

```lua
--调用close即可:
stream.close();
```

## 路由转发(实现中):
作为例子,这里假定一个游戏服务集群由一下这些进程构成:
- 路由转发进程(router),集群中运行多个,但我们先考虑一个的情况. 
- 邮件服务进程(mailsvr),根据用户名哈希来分担负载
- 房间匹配服务进程(matchsvr),运行两个,主从备份.
- 游戏大厅服务器(gamnesvr),运行若干个,按在线人数负载分担.

为了实现这个路由转发,我们把所有的服务进程都连接到router,以它为中心做中转.  
另外,还需要引入服务进程标识(service id),它通常是服务进程启动时指定的(如命令行参数).
实际上它是个uint32_t整数,最高字节[1-255]被用做服务类型(service class),其余3字节用作实例标识(instance id).  
也就是说: service_id = (service_class << 24) | instance_id;  
实现中约定, service_class, instance_id均不为0

现在考虑router如何实现这个数据转发.  
最简单的,当然可以通过上面的远程调用来实现转发.  
但是这样有个效率问题,应该序列化数据完全没必须要在router展开,然后再重新序列化.  
作为一个业务繁忙的数据转发器,这种无谓的消耗是无法接受的.  
在数据转发逻辑中,最关键的是维护一个转发目标的集合.   
有了这个集合,我们就能实现主从,哈希,随机,指定目标等方式的转发.  
基于这个思路,我们把转发操作本身实现在C++层面,但是把集合的维护交给lua控制.  
当有服务进程连接或者断开时,可以通过下面的方式更新转发表.  

```lua
--socket_mgr内部会对同一类型的instance_id排序(升序)
--如果连接断开(或未连接)时,需要保留空位(固定哈希),可以把token传0,需要删除则设置token为nil
--目前不支持权重参数设置,可以为一个连接配置多个instance_id来实现
--主从备份模式时,永远转发给排序后的第一个非0的instance_id
socket_mgr.route(service_id, stream.token);
```

这样,比如gamesvr想把玩家加入战斗匹配,就可以额做类似这样的调用:

```lua
--注意,matchsvr的主从备份模式对调用者而言应该是透明的
--router在做消息转发的时候,会根据主从,哈希等模式参数来把消息转发到正确的目标. 
--当然,主从切换时,还是会对个别请求产生影响
socket = socket_mgr.connect("127.0.0.1", 2000);
function call_matchsvr(msg, ...)
	--将后面的参数打包给router,让它按规则(即主从备份master)转发给matchsvr
	socket.forward(master, matchsvr, msg, ...);
end

call_matchsvr("join_match", player_id, match_mode);
```


## 模块扩展(TODO)
即如何方便的进行自定义扩展模块(dll,so之类),待定.


