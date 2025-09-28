! QQ机器人 Factor实现
! 基于栈式编程的连接性语言实现

USING: accessors assocs calendar combinators http.client io
json kernel math math.parser namespaces sequences strings
threads timers urls ;

IN: simple-bot

! 配置常量
CONSTANT: NAPCAT-URL "http://localhost:3000"
CONSTANT: GEMINI-API-URL ""
CONSTANT: GEMINI-API-KEY ""
CONSTANT: GROUP-ID ""
CONSTANT: BOT-QQ ""

! 全局状态
SYMBOL: last-message-time
0 last-message-time set-global

! 日志函数
: log ( message -- )
    now timestamp>string " [INFO] " rot 3append print flush ;

: error-log ( message -- )
    now timestamp>string " [ERROR] " rot 3append print flush ;

: success-log ( message -- )
    now timestamp>string " [SUCCESS] " rot 3append print flush ;

! HTTP请求封装
: make-post-request ( url data -- response )
    [ <post-request> ] dip >>post-data
    [ "application/json" "Content-Type" set-header ] keep
    http-request nip ;

: make-get-request ( url -- response )
    <get-request> http-request nip ;

! 获取群消息历史
: get-messages ( -- json )
    NAPCAT-URL "/get_group_msg_history" append
    H{ { "group_id" GROUP-ID } { "count" 40 } } >json
    make-post-request ;

! 发送群消息
: send-message ( message -- )
    [ NAPCAT-URL "/send_group_msg" append ]
    [ H{ { "group_id" GROUP-ID } { "message" } } >json ] bi
    make-post-request drop ;

! JSON解析辅助
: get-status ( json -- status )
    "status" swap at ;

: get-messages-array ( json -- messages )
    "data" swap at "messages" swap at ;

! 提取消息字段
: extract-message-fields ( msg -- time user-id raw-message )
    [ "time" swap at ]
    [ "user_id" swap at ]
    [ "raw_message" swap at ] tri ;

! 检查是否为新消息
: is-new-message? ( time user-id -- ? )
    BOT-QQ = not swap last-message-time get-global > and ;

! 更新最后消息时间
: update-last-time ( time -- )
    dup last-message-time get-global >
    [ last-message-time set-global ] [ drop ] if ;

! 格式化消息历史
: format-message ( time user-id raw-message -- formatted )
    [
        unix-time>timestamp timestamp>string " " split first
        " 用户" rot append ": " append rot append
    ] keep
    BOT-QQ = [ " [我自己]" append ] when ;

! 构建Gemini API载荷
: build-gemini-payload ( prompt -- json-string )
    [
        "现在你不再是个AI助理，没必要帮助用户解决任何问题,你的任务是扮演一位叫做楠楠的少男"
        "\\n\\n用户消息: " rot append
        "系统指令: " swap append
    ] keep
    H{
        { "contents"
            { H{
                { "role" "user" }
                { "parts" { H{ { "text" } } } }
            } }
        }
        { "tools"
            { H{
                { "functionDeclarations"
                    {
                        H{
                            { "name" "send_group_message" }
                            { "description" "发送消息到QQ群" }
                            { "parameters" H{
                                { "type" "object" }
                                { "properties" H{
                                    { "message" H{
                                        { "type" "string" }
                                        { "description" "要发送的消息内容" }
                                    } }
                                } }
                                { "required" { "message" } }
                            } }
                        }
                        H{
                            { "name" "end" }
                            { "description" "结束对话" }
                            { "parameters" H{
                                { "type" "object" }
                                { "properties" H{
                                    { "reason" H{
                                        { "type" "string" }
                                        { "description" "结束原因" }
                                    } }
                                } }
                                { "required" { "reason" } }
                            } }
                        }
                    }
                }
            } }
        }
    } 2dup "contents" swap at first "parts" swap at first "text" rot put >json ;

! 调用Gemini API
: call-gemini-api ( prompt -- response )
    build-gemini-payload
    GEMINI-API-URL <post-request>
        [ >>post-data ]
        [ GEMINI-API-KEY "x-goog-api-key" set-header ] bi
    http-request nip ;

! 解析AI响应中的函数调用
: extract-function-calls ( response -- calls )
    "candidates" swap at
    [ empty? not ] filter
    first "content" swap at "parts" swap at
    [ "functionCall" swap at* nip ] filter ;

! 执行AI响应
: execute-ai-response ( response -- continue? )
    extract-function-calls
    [
        [ "name" swap at ]
        [ "args" swap at ] bi
        2dup "send_group_message" =
        [
            drop "message" swap at
            dup "发送消息: " prepend success-log
            send-message
        ] [
            2dup "end" =
            [
                drop "reason" swap at
                dup "结束对话: " prepend success-log
                drop f
            ] [ 2drop ] if
        ] if
    ] each
    t ;

! 构建AI提示词
: build-prompt ( chat-history new-messages -- prompt )
    now timestamp>string
    "当前时间: " swap append "\\n"
    "群聊ID: " GROUP-ID append "\\n"
    "我的QQ号: " BOT-QQ append "\\n\\n"
    "💬 群聊历史记录:\\n" append
    rot append "\\n"
    "------ 以下是新消息 ------\\n" append
    swap append
    "------ 以上是所有新消息内容 ------\\n\\n" append
    "🧠 请仔细分析当前对话状态，然后决定下一步操作:\\n\\n" append
    "1. 参与判断 - 是否需要回复:\\n" append
    "   - 消息是否与我相关或值得参与？\\n" append
    "   - 如果话题无聊且无法开涮群友，直接调用end工具\\n" append
    "   - 如果值得吐槽或有趣，用send_group_message简短回复\\n\\n" append
    "2. 回复风格:\\n" append
    "   - 简洁回复，尽量20字以内\\n" append
    "   - 多用吐槽，少用解释\\n" append
    "   - 像真实的23岁网友一样说话\\n\\n" append
    "记住：绝不直接返回文本，必须使用send_group_message或end工具！" append ;

! 处理新消息
: process-messages ( json -- )
    get-messages-array
    [ extract-message-fields is-new-message? ] filter
    dup empty? not
    [
        [ [ extract-message-fields 3drop update-last-time ] each ]
        [ [ extract-message-fields format-message ] map "\\n" join ]
        [ length number>string " 条新消息" append "检测到 " prepend log ] tri

        ! 获取完整历史
        get-messages get-messages-array
        [ extract-message-fields format-message ] map "\\n" join

        ! 构建提示并调用AI
        swap build-prompt
        dup "正在处理新消息..." log
        call-gemini-api execute-ai-response drop
    ] [ drop ] if ;

! 主循环
: bot-loop ( -- )
    [
        [
            "检查新消息..." log
            get-messages
            dup get-status "ok" =
            [ process-messages ]
            [ drop "API调用失败" error-log ] if

            5 seconds sleep
        ] loop
    ] in-thread ;

! 启动机器人
: start-bot ( -- )
    "简化版QQ机器人启动 (Factor版本)" log
    "监听群: " GROUP-ID append log
    bot-loop ;

! 主函数
: main ( -- ) start-bot ;

! 运行: Factor simple-bot.factor -run=main