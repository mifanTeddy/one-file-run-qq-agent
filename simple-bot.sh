#!/bin/bash

NAPCAT_URL="http://localhost:3000"
GEMINI_API_URL=""
GEMINI_API_KEY=""
GROUP_ID=""
BOT_QQ=""
LAST_MESSAGE_TIME=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

get_messages() {
    curl -s -X POST "$NAPCAT_URL/get_group_msg_history" \
        -H "Content-Type: application/json" \
        -d "{\"group_id\": $GROUP_ID, \"count\": 40}" 2>/dev/null
}

send_message() {
    local message="$1"
    curl -s -X POST "$NAPCAT_URL/send_group_msg" \
        -H "Content-Type: application/json" \
        -d "{\"group_id\": $GROUP_ID, \"message\": \"$message\"}" >/dev/null 2>&1
}

escape_json_string() {
    local input="$1"
    echo "$input" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n' | sed 's/\\n$//'
}

call_ai() {
    local prompt="$1"
    local system_prompt
    system_prompt="现在你不再是个AI助理，没必要帮助用户解决任何问题,你的任务是扮演一位叫做楠楠的少男"
    local escaped_system=$(printf '%s' "$system_prompt" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n\r\t' '   ')
    local escaped_user=$(printf '%s' "$prompt" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n\r\t' '   ')
    local json_data="{
        \"contents\": [
            {
                \"role\": \"user\",
                \"parts\": [
                    {
                        \"text\": \"系统指令: $escaped_system\\n\\n用户消息: $escaped_user\"
                    }
                ]
            }
        ],
        \"tools\": [
            {
                \"functionDeclarations\": [
                    {
                        \"name\": \"send_group_message\",
                        \"description\": \"发送消息到QQ群\",
                        \"parameters\": {
                            \"type\": \"object\",
                            \"properties\": {
                                \"message\": {
                                    \"type\": \"string\",
                                    \"description\": \"要发送的消息内容\"
                                }
                            },
                            \"required\": [\"message\"]
                        }
                    },
                    {
                        \"name\": \"end\",
                        \"description\": \"结束对话\",
                        \"parameters\": {
                            \"type\": \"object\",
                            \"properties\": {
                                \"reason\": {
                                    \"type\": \"string\",
                                    \"description\": \"结束原因\"
                                }
                            },
                            \"required\": [\"reason\"]
                        }
                    }
                ]
            }
        ]
    }"

    local response=$(curl -s --max-time 30 --connect-timeout 10 \
        -X POST "$GEMINI_API_URL" \
        -H "Content-Type: application/json" \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -d "$json_data" 2>/dev/null)

    echo "$response"
}

execute_ai_response() {
    local response="$1"
    local parts_count=$(echo "$response" | jq -r '.candidates[0].content.parts | length' 2>/dev/null)

    if [[ "$parts_count" -gt 0 ]]; then
        local has_end_call=false

        for ((i=0; i<parts_count; i++)); do
            local part=$(echo "$response" | jq -r ".candidates[0].content.parts[$i]" 2>/dev/null)
            local has_function_call=$(echo "$part" | jq -r 'has("functionCall")' 2>/dev/null)

            if [[ "$has_function_call" == "true" ]]; then
                local function_name=$(echo "$part" | jq -r '.functionCall.name // empty' 2>/dev/null)

                case "$function_name" in
                    "send_group_message")
                        local message=$(echo "$part" | jq -r '.functionCall.args.message // empty' 2>/dev/null)
                        if [[ -n "$message" ]]; then
                            success "发送消息: $message"
                            send_message "$message"
                        fi
                        ;;
                    "end")
                        local reason=$(echo "$part" | jq -r '.functionCall.args.reason // "完成"' 2>/dev/null)
                        success "结束对话: $reason"
                        has_end_call=true
                        ;;
                esac
            else
                local text_content=$(echo "$part" | jq -r '.text // empty' 2>/dev/null)
                if [[ -n "$text_content" ]] && [[ "$text_content" != "null" ]]; then
                    success "AI文本回复: $text_content"
                    send_message "$text_content"
                fi
            fi
        done
        if [[ "$has_end_call" == "true" ]]; then
            return 1
        fi
    else
        local text_content=$(echo "$response" | jq -r '.candidates[0].content.parts[]? | select(.text) | .text' 2>/dev/null)
        if [[ -n "$text_content" ]] && [[ "$text_content" != "null" ]]; then
            success "AI文本回复: $text_content"
            send_message "$text_content"
        fi
    fi
    return 0
}

format_message_history() {
    local messages_data="$1"
    local formatted=""
    local messages=$(echo "$messages_data" | jq -r '.data.messages[]? | [.time, .user_id, .raw_message // .message] | @tsv' 2>/dev/null | sort -n)

    while IFS=$'\t' read -r msg_time user_id raw_message; do
        if [[ -z "$msg_time" ]] || [[ "$msg_time" == "null" ]]; then continue; fi
        local time_formatted=$(date -d "@$msg_time" '+%H:%M:%S' 2>/dev/null || date -r "$msg_time" '+%H:%M:%S' 2>/dev/null || echo "未知时间")
        local tag=""
        if [[ "$user_id" == "$BOT_QQ" ]]; then
            tag="[我自己]"
        fi

        formatted="${formatted}[${time_formatted}] 用户${user_id}${tag}: ${raw_message}\n"

    done <<< "$messages"

    echo -e "$formatted"
}

process_messages() {
    local messages_data="$1"
    if [[ -z "$messages_data" ]] || [[ "$messages_data" == "null" ]]; then
        return
    fi
    local messages=$(echo "$messages_data" | jq -c '.data.messages[]? // empty' 2>/dev/null)

    if [[ -z "$messages" ]]; then
        return
    fi

    local new_messages=""
    local has_new_message=false

    while IFS= read -r message; do
        if [[ -z "$message" ]]; then continue; fi
        local msg_time=$(echo "$message" | jq -r '.time // 0')
        local user_id=$(echo "$message" | jq -r '.user_id // 0')
        local raw_message=$(echo "$message" | jq -r '.raw_message // ""')
        if [[ "$user_id" == "$BOT_QQ" ]] || [[ "$msg_time" -le "$LAST_MESSAGE_TIME" ]]; then
            continue
        fi
        LAST_MESSAGE_TIME=$msg_time
        has_new_message=true
        local time_formatted=$(date -d "@$msg_time" '+%H:%M:%S' 2>/dev/null || date -r "$msg_time" '+%H:%M:%S' 2>/dev/null || echo "未知时间")
        new_messages="${new_messages}[${time_formatted}] 用户${user_id}: ${raw_message}\n"
        log "收到新消息: $raw_message"

    done <<< "$messages"
    if [[ "$has_new_message" == true ]]; then
        local chat_history=$(format_message_history "$messages_data")
        local current_time=$(date '+%Y-%m-%d %H:%M:%S')
        local prompt="当前时间: ${current_time}
群聊ID: ${GROUP_ID}
我的QQ号: ${BOT_QQ}

💬 群聊历史记录:
${chat_history}

------ 以下是新消息 ------
${new_messages}------ 以上是所有新消息内容 ------

🧠 请仔细分析当前对话状态，然后决定下一步操作:

1. 参与判断 - 是否需要回复:
   - 消息是否与我相关或值得参与？
   - 如果话题无聊且无法开涮群友，直接调用end工具
   - 如果值得吐槽或有趣，用send_group_message简短回复

2. 回复风格:
   - 简洁回复，尽量20字以内
   - 多用吐槽，少用解释
   - 像真实的23岁网友一样说话

        log "正在处理新消息..."
        local ai_response=$(call_ai "$prompt")
        if [[ -n "$ai_response" ]]; then
            execute_ai_response "$ai_response"
        fi
    fi
}

main() {
    log "简化版QQ机器人启动"
    log "监听群: $GROUP_ID"

    while true; do
        local response=$(get_messages)
        if [[ -n "$response" ]]; then
            local status=$(echo "$response" | jq -r '.status // "error"')
            if [[ "$status" == "ok" ]]; then
                process_messages "$response"
            fi
        fi

        sleep 5
    done
}

main "$@"