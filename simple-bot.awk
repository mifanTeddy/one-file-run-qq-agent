#!/usr/bin/gawk -f

BEGIN {
    NAPCAT_URL = "http://localhost:3000"
    GEMINI_API_URL = ""
    GEMINI_API_KEY = ""
    GROUP_ID = ""
    BOT_QQ = ""
    LAST_MESSAGE_TIME = 0
}

function log_message(type, msg) {
    system("date '+[%H:%M:%S]'")
    printf " [%s] %s\n", type, msg
    fflush()
}

function http_post(url, data, headers,    cmd, response) {
    cmd = sprintf("curl -s -X POST '%s' -H 'Content-Type: application/json'", url)
    if (headers != "") {
        cmd = cmd " " headers
    }
    cmd = cmd " -d '" data "'"

    while ((cmd | getline response) > 0) {
        return response
    }
    close(cmd)
    return ""
}

function escape_json(str) {
    gsub(/\\/, "\\\\", str)
    gsub(/"/, "\\\"", str)
    gsub(/\n/, "\\n", str)
    return str
}

function extract_json_value(json, key,    start, end, value) {
    start = index(json, "\"" key "\":")
    if (start == 0) return ""

    start = index(substr(json, start), ":") + start
    while (substr(json, start, 1) == " ") start++

    if (substr(json, start, 1) == "\"") {
        start++
        end = index(substr(json, start), "\"") + start - 1
        value = substr(json, start, end - start)
    } else {
        end = index(substr(json, start), ",")
        if (end == 0) end = index(substr(json, start), "}")
        if (end == 0) end = length(json) - start + 1
        end = end + start - 1
        value = substr(json, start, end - start)
        gsub(/[ \t\n}]/, "", value)
    }
    return value
}

function get_messages(    data, response) {
    data = sprintf("{\"group_id\": %s, \"count\": 40}", GROUP_ID)
    response = http_post(NAPCAT_URL "/get_group_msg_history", data)
    return response
}

function send_message(message,    data) {
    message = escape_json(message)
    data = sprintf("{\"group_id\": %s, \"message\": \"%s\"}", GROUP_ID, message)
    http_post(NAPCAT_URL "/send_group_msg", data)
}

function parse_messages(json,    messages_start, messages_end, msg_json, i, msg_count) {
    delete messages
    msg_count = 0

    messages_start = index(json, "\"messages\":")
    if (messages_start == 0) return 0

    messages_start = index(substr(json, messages_start), "[") + messages_start
    messages_end = messages_start

    for (i = messages_start + 1; i <= length(json); i++) {
        if (substr(json, i, 1) == "]") {
            messages_end = i
            break
        }
    }

    msg_json = substr(json, messages_start + 1, messages_end - messages_start - 1)

    split_messages(msg_json, msg_count)
    return msg_count
}

function split_messages(msg_json, msg_count,    parts, i, current_msg, brace_count, char) {
    current_msg = ""
    brace_count = 0

    for (i = 1; i <= length(msg_json); i++) {
        char = substr(msg_json, i, 1)

        if (char == "{") {
            brace_count++
            current_msg = current_msg char
        } else if (char == "}") {
            current_msg = current_msg char
            brace_count--

            if (brace_count == 0 && current_msg != "") {
                messages[msg_count]["time"] = extract_json_value(current_msg, "time")
                messages[msg_count]["user_id"] = extract_json_value(current_msg, "user_id")
                messages[msg_count]["raw_message"] = extract_json_value(current_msg, "raw_message")
                msg_count++
                current_msg = ""
            }
        } else if (brace_count > 0) {
            current_msg = current_msg char
        }
    }
}

function detect_new_messages(msg_count,    i, new_count, msg_time) {
    delete new_messages
    new_count = 0

    for (i = 0; i < msg_count; i++) {
        msg_time = int(messages[i]["time"])
        if (messages[i]["user_id"] != BOT_QQ && msg_time > LAST_MESSAGE_TIME) {
            new_messages[new_count]["time"] = messages[i]["time"]
            new_messages[new_count]["user_id"] = messages[i]["user_id"]
            new_messages[new_count]["raw_message"] = messages[i]["raw_message"]
            new_count++

            if (msg_time > LAST_MESSAGE_TIME) {
                LAST_MESSAGE_TIME = msg_time
            }
        }
    }
    return new_count
}

function format_message_history(msg_count,    i, formatted, time_str, tag) {
    formatted = ""
    for (i = 0; i < msg_count; i++) {
        time_str = strftime("%H:%M:%S", messages[i]["time"])
        tag = (messages[i]["user_id"] == BOT_QQ) ? "[我自己]" : ""
        formatted = formatted sprintf("[%s] 用户%s%s: %s\\n",
            time_str, messages[i]["user_id"], tag, messages[i]["raw_message"])
    }
    return formatted
}

function format_new_messages(new_count,    i, formatted, time_str) {
    formatted = ""
    for (i = 0; i < new_count; i++) {
        time_str = strftime("%H:%M:%S", new_messages[i]["time"])
        formatted = formatted sprintf("[%s] 用户%s: %s\\n",
            time_str, new_messages[i]["user_id"], new_messages[i]["raw_message"])
    }
    return formatted
}

function build_prompt(chat_history, new_msg_text,    current_time, prompt) {
    current_time = strftime("%Y-%m-%d %H:%M:%S")

    prompt = sprintf("当前时间: %s\\n群聊ID: %s\\n我的QQ号: %s\\n\\n💬 群聊历史记录:\\n%s\\n------ 以下是新消息 ------\\n%s------ 以上是所有新消息内容 ------\\n\\n🧠 请仔细分析当前对话状态，然后决定下一步操作:\\n\\n1. 参与判断 - 是否需要回复:\\n   - 消息是否与我相关或值得参与？\\n   - 如果话题无聊且无法开涮群友，直接调用end工具\\n   - 如果值得吐槽或有趣，用send_group_message简短回复\\n\\n2. 回复风格:\\n   - 简洁回复，尽量20字以内\\n   - 多用吐槽，少用解释\\n   - 像真实的23岁网友一样说话\\n\\n记住：绝不直接返回文本，必须使用send_group_message或end工具！",
        current_time, GROUP_ID, BOT_QQ, chat_history, new_msg_text)

    return prompt
}

function build_gemini_payload(prompt,    system_prompt, escaped_system, escaped_user, json_data) {
    system_prompt = "现在你不再是个AI助理，没必要帮助用户解决任何问题,你的任务是扮演一位叫做楠楠的少男"
    escaped_system = escape_json(system_prompt)
    escaped_user = escape_json(prompt)

    json_data = sprintf("{\"contents\": [{\"role\": \"user\",\"parts\": [{\"text\": \"系统指令: %s\\n\\n用户消息: %s\"}]}],\"tools\": [{\"functionDeclarations\": [{\"name\": \"send_group_message\",\"description\": \"发送消息到QQ群\",\"parameters\": {\"type\": \"object\",\"properties\": {\"message\": {\"type\": \"string\",\"description\": \"要发送的消息内容\"}},\"required\": [\"message\"]}},{\"name\": \"end\",\"description\": \"结束对话\",\"parameters\": {\"type\": \"object\",\"properties\": {\"reason\": {\"type\": \"string\",\"description\": \"结束原因\"}},\"required\": [\"reason\"]}}]}]}",
        escaped_system, escaped_user)

    return json_data
}

function call_ai(prompt,    json_data, headers, response) {
    json_data = build_gemini_payload(prompt)
    headers = sprintf("-H 'x-goog-api-key: %s'", GEMINI_API_KEY)
    response = http_post(GEMINI_API_URL, json_data, headers)
    return response
}

function execute_ai_response(response,    parts_start, parts_end, parts_json, func_pos, func_name, args_start, args_end, args_json, message, reason, has_end) {
    parts_start = index(response, "\"parts\":")
    if (parts_start == 0) return 1

    parts_start = index(substr(response, parts_start), "[") + parts_start
    parts_end = find_matching_bracket(response, parts_start, "[", "]")
    if (parts_end == 0) return 1

    parts_json = substr(response, parts_start, parts_end - parts_start + 1)
    has_end = 0

    func_pos = index(parts_json, "\"functionCall\":")
    while (func_pos > 0) {
        func_name = extract_function_name(parts_json, func_pos)

        if (func_name == "send_group_message") {
            args_json = extract_function_args(parts_json, func_pos)
            message = extract_json_value(args_json, "message")
            if (message != "") {
                log_message("SUCCESS", "发送消息: " message)
                send_message(message)
            }
        } else if (func_name == "end") {
            args_json = extract_function_args(parts_json, func_pos)
            reason = extract_json_value(args_json, "reason")
            if (reason == "") reason = "完成"
            log_message("SUCCESS", "结束对话: " reason)
            has_end = 1
        }

        parts_json = substr(parts_json, func_pos + 10)
        func_pos = index(parts_json, "\"functionCall\":")
    }

    if (has_end) return 0

    text_pos = index(parts_json, "\"text\":")
    if (text_pos > 0) {
        text_content = extract_json_value(parts_json, "text")
        if (text_content != "") {
            log_message("SUCCESS", "AI文本回复: " text_content)
            send_message(text_content)
        }
    }

    return 1
}

function extract_function_name(json, start_pos,    name_pos) {
    name_pos = index(substr(json, start_pos), "\"name\":")
    if (name_pos > 0) {
        return extract_json_value(substr(json, start_pos + name_pos - 10), "name")
    }
    return ""
}

function extract_function_args(json, start_pos,    args_pos, obj_start, obj_end) {
    args_pos = index(substr(json, start_pos), "\"args\":")
    if (args_pos > 0) {
        obj_start = index(substr(json, start_pos + args_pos), "{") + start_pos + args_pos - 1
        obj_end = find_matching_bracket(json, obj_start, "{", "}")
        if (obj_end > obj_start) {
            return substr(json, obj_start, obj_end - obj_start + 1)
        }
    }
    return ""
}

function find_matching_bracket(text, start_pos, open_char, close_char,    pos, level, char) {
    level = 1
    pos = start_pos + 1

    while (pos <= length(text) && level > 0) {
        char = substr(text, pos, 1)
        if (char == open_char) {
            level++
        } else if (char == close_char) {
            level--
        }
        pos++
    }

    if (level == 0) {
        return pos - 1
    }
    return 0
}

function process_messages(    response, status, msg_count, new_count, chat_history, new_msg_text, prompt, ai_response) {
    response = get_messages()
    if (response == "") {
        log_message("ERROR", "无法获取消息")
        return
    }

    status = extract_json_value(response, "status")
    if (status != "ok") {
        log_message("ERROR", "API返回状态: " status)
        return
    }

    msg_count = parse_messages(response)
    if (msg_count == 0) return

    new_count = detect_new_messages(msg_count)
    if (new_count > 0) {
        chat_history = format_message_history(msg_count)
        new_msg_text = format_new_messages(new_count)
        prompt = build_prompt(chat_history, new_msg_text)

        log_message("INFO", "检测到 " new_count " 条新消息")
        log_message("INFO", "正在处理新消息...")

        ai_response = call_ai(prompt)
        if (ai_response != "") {
            execute_ai_response(ai_response)
        }
    }
}

BEGIN {
    log_message("INFO", "简化版QQ机器人启动 (AWK版本)")
    log_message("INFO", "监听群: " GROUP_ID)

    while (1) {
        process_messages()
        system("sleep 5")
    }
}