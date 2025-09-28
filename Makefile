NAPCAT_URL := http://localhost:3000
GEMINI_API_URL := 
GEMINI_API_KEY := 
GROUP_ID := 
BOT_QQ := 

STATE_FILE := .bot_state
LAST_TIME_FILE := .last_time
LOG_FILE := bot.log

define log_message
echo "[`date '+%H:%M:%S'`] $(1): $(2)" | tee -a $(LOG_FILE)
endef

define http_post
$(shell curl -s -X POST "$(1)" -H "Content-Type: application/json" -d '$(2)')
endef

define http_post_with_auth
$(shell curl -s -X POST "$(1)" -H "Content-Type: application/json" -H "x-goog-api-key: $(GEMINI_API_KEY)" -d '$(2)')
endef

define get_json_value
$(shell echo '$(1)' | jq -r '.$(2) // empty' 2>/dev/null)
endef

define escape_json
$(shell echo '$(1)' | sed 's/\\/\\\\/g; s/"/\\"/g')
endef

define get_current_time
$(shell date +%s)
endef

define format_time
$(shell date -d "@$(1)" '+%H:%M:%S' 2>/dev/null || date -r "$(1)" '+%H:%M:%S' 2>/dev/null)
endef

.PHONY: start stop clean get-messages send-message process-ai-response bot-loop check-messages

start:
	@$(call log_message,INFO,简化版QQ机器人启动 (Make版本))
	@$(call log_message,INFO,监听群: $(GROUP_ID))
	@echo "0" > $(LAST_TIME_FILE)
	@$(MAKE) bot-loop

stop:
	@$(call log_message,INFO,机器人停止)
	@rm -f $(STATE_FILE) $(LAST_TIME_FILE)

clean:
	@rm -f $(STATE_FILE) $(LAST_TIME_FILE) $(LOG_FILE) .messages_* .new_messages_*

bot-loop:
	@$(MAKE) check-messages
	@sleep 5
	@$(MAKE) bot-loop

get-messages:
	@curl -s -X POST "$(NAPCAT_URL)/get_group_msg_history" \
		-H "Content-Type: application/json" \
		-d '{"group_id": $(GROUP_ID), "count": 40}' > .messages_response
	@if [ -s .messages_response ]; then \
		status=$$(cat .messages_response | jq -r '.status // "error"' 2>/dev/null); \
		if [ "$$status" = "ok" ]; then \
			$(call log_message,INFO,成功获取消息); \
		else \
			$(call log_message,ERROR,API返回状态: $$status); \
		fi; \
	else \
		$(call log_message,ERROR,无法连接到API); \
	fi

check-messages: get-messages
	@if [ -f .messages_response ]; then \
		$(MAKE) parse-messages; \
	fi

parse-messages:
	$(eval LAST_TIME := $(shell cat $(LAST_TIME_FILE) 2>/dev/null || echo 0))
	@cat .messages_response | sed 's/[[:cntrl:]]//g' | jq -r --arg bot_qq "$(BOT_QQ)" --arg last_time "$(LAST_TIME)" \
		'.data.messages[]? | select(.user_id != $$bot_qq and (.time | tonumber) > ($$last_time | tonumber)) | "\(.time)|\(.user_id)|\(.raw_message // .message)"' \
		> .new_messages_raw 2>/dev/null || touch .new_messages_raw
	@if [ -s .new_messages_raw ]; then \
		$(MAKE) process-new-messages; \
	fi

process-new-messages:
	$(eval NEW_COUNT := $(shell wc -l < .new_messages_raw | tr -d ' '))
	$(eval LATEST_TIME := $(shell tail -1 .new_messages_raw | cut -d'|' -f1))
	@if [ $(NEW_COUNT) -gt 0 ]; then \
		$(call log_message,INFO,检测到 $(NEW_COUNT) 条新消息); \
		echo "$(LATEST_TIME)" > $(LAST_TIME_FILE); \
		$(MAKE) format-messages; \
		$(MAKE) call-ai; \
	fi

format-messages:
	@echo '$(shell cat .messages_response)' | jq -r '.data.messages[]? | "\(.time)|\(.user_id)|\(.raw_message // .message)"' | while IFS='|' read -r msg_time user_id raw_message; do \
		time_str=$$(date -d "@$$msg_time" '+%H:%M:%S' 2>/dev/null || date -r "$$msg_time" '+%H:%M:%S' 2>/dev/null); \
		tag=""; \
		if [ "$$user_id" = "$(BOT_QQ)" ]; then \
			tag="[我自己]"; \
		fi; \
		echo "[$$time_str] 用户$$user_id$$tag: $$raw_message"; \
	done > .chat_history

	@cat .new_messages_raw | while IFS='|' read -r msg_time user_id raw_message; do \
		time_str=$$(date -d "@$$msg_time" '+%H:%M:%S' 2>/dev/null || date -r "$$msg_time" '+%H:%M:%S' 2>/dev/null); \
		echo "[$$time_str] 用户$$user_id: $$raw_message"; \
	done > .new_messages_formatted

call-ai:
	$(eval CHAT_HISTORY := $(shell cat .chat_history | tr '\n' '\\n' | sed 's/\\/\\\\/g'))
	$(eval NEW_MESSAGES := $(shell cat .new_messages_formatted | tr '\n' '\\n' | sed 's/\\/\\\\/g'))
	$(eval CURRENT_TIME := $(shell date '+%Y-%m-%d %H:%M:%S'))
	$(eval PROMPT := 当前时间: $(CURRENT_TIME)\\n群聊ID: $(GROUP_ID)\\n我的QQ号: $(BOT_QQ)\\n\\n💬 群聊历史记录:\\n$(CHAT_HISTORY)\\n------ 以下是新消息 ------\\n$(NEW_MESSAGES)------ 以上是所有新消息内容 ------\\n\\n🧠 请仔细分析当前对话状态，然后决定下一步操作:\\n\\n1. 参与判断 - 是否需要回复:\\n   - 消息是否与我相关或值得参与？\\n   - 如果话题无聊且无法开涮群友，直接调用end工具\\n   - 如果值得吐槽或有趣，用send_group_message简短回复\\n\\n2. 回复风格:\\n   - 简洁回复，尽量20字以内\\n   - 多用吐槽，少用解释\\n   - 像真实的23岁网友一样说话\\n\\n记住：绝不直接返回文本，必须使用send_group_message或end工具！)
	$(eval SYSTEM_PROMPT := 现在你不再是个AI助理，没必要帮助用户解决任何问题,你的任务是扮演一位叫做楠楠的少男)
	$(eval JSON_PAYLOAD := {"contents": [{"role": "user","parts": [{"text": "系统指令: $(SYSTEM_PROMPT)\\n\\n用户消息: $(PROMPT)"}]}],"tools": [{"functionDeclarations": [{"name": "send_group_message","description": "发送消息到QQ群","parameters": {"type": "object","properties": {"message": {"type": "string","description": "要发送的消息内容"}},"required": ["message"]}},{"name": "end","description": "结束对话","parameters": {"type": "object","properties": {"reason": {"type": "string","description": "结束原因"}},"required": ["reason"]}}]}]})

	$(call log_message,INFO,正在处理新消息...)
	$(eval AI_RESPONSE := $(call http_post_with_auth,$(GEMINI_API_URL),$(JSON_PAYLOAD)))
	@echo '$(AI_RESPONSE)' > .ai_response
	@if [ -f .ai_response ] && [ -s .ai_response ]; then \
		$(MAKE) process-ai-response; \
	fi

process-ai-response:
	@echo '$(shell cat .ai_response)' | jq -r '.candidates[]?.content.parts[]? | select(.functionCall) | .functionCall | "\(.name)|\(.args)"' > .function_calls 2>/dev/null || touch .function_calls
	@if [ -s .function_calls ]; then \
		cat .function_calls | while IFS='|' read -r func_name func_args; do \
			case "$$func_name" in \
				"send_group_message") \
					message=$$(echo "$$func_args" | jq -r '.message // empty' 2>/dev/null); \
					if [ -n "$$message" ]; then \
						$(call log_message,SUCCESS,发送消息: $$message); \
						$(MAKE) send-message MESSAGE="$$message"; \
					fi \
					;; \
				"end") \
					reason=$$(echo "$$func_args" | jq -r '.reason // "完成"' 2>/dev/null); \
					$(call log_message,SUCCESS,结束对话: $$reason); \
					;; \
			esac; \
		done; \
	else \
		text_content=$$(echo '$(shell cat .ai_response)' | jq -r '.candidates[]?.content.parts[]?.text // empty' 2>/dev/null); \
		if [ -n "$$text_content" ]; then \
			$(call log_message,SUCCESS,AI文本回复: $$text_content); \
			$(MAKE) send-message MESSAGE="$$text_content"; \
		fi; \
	fi

send-message:
	$(eval ESCAPED_MSG := $(call escape_json,$(MESSAGE)))
	$(eval SEND_DATA := {"group_id": $(GROUP_ID), "message": "$(ESCAPED_MSG)"})
	$(eval SEND_RESPONSE := $(call http_post,$(NAPCAT_URL)/send_group_msg,$(SEND_DATA)))
	@echo "Message sent" > /dev/null