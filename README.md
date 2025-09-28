# 简化版QQ机器人 - 多语言实现

一个基于AI的QQ群聊机器人，采用多种编程语言实现相同功能，展示不同编程范式和技术栈的应用。

## 功能特点

- 🤖 **AI驱动**: 基于Google Gemini API的智能对话
- 💬 **QQ群聊**: 通过NapCat API连接QQ群
- 🎭 **个性化**: 扮演名为"楠楠"的23岁网友，具有独特的聊天风格
- 🔄 **实时监听**: 持续监听群消息并智能回复
- 🛠️ **多语言**: 提供多种编程语言实现

## 实现版本

| 文件 | 语言/技术 | 特点 |
|-----|----------|------|
| `simple-bot.sh` | Bash | Shell脚本，依赖curl和jq |
| `simple-bot.awk` | AWK | 文本处理语言，轻量级实现 |
| `simple-bot.factor` | Factor | 栈式编程语言，函数式风格 |
| `Makefile` | Make | 构建工具实现，展示Make的编程能力 |
| `Excel_QQ_Bot_VBA.txt` | VBA | Excel宏实现，办公软件集成 |

## 环境要求

### 通用依赖
- **NapCat**: QQ消息API服务 (默认端口3000)
- **Gemini API**: Google AI服务访问权限

### 各版本特定依赖

#### Bash版本 (`simple-bot.sh`)
```bash
# 系统要求
- bash
- curl
- jq
- date

# 运行
chmod +x simple-bot.sh
./simple-bot.sh
```

#### AWK版本 (`simple-bot.awk`)
```bash
# 系统要求
- gawk (GNU AWK)

# 运行
chmod +x simple-bot.awk
./simple-bot.awk
```

#### Factor版本 (`simple-bot.factor`)
```bash
# 安装Factor语言环境
# 下载: https://factorcode.org/

# 运行
factor simple-bot.factor
```

#### Make版本 (`Makefile`)
```bash
# 系统要求
- make
- curl
- jq

# 运行
make start
```

#### Excel VBA版本
```
1. 打开Excel
2. 启用宏功能
3. 导入VBA代码
4. 配置参数并运行
```

## 配置说明

在使用任何版本之前，需要配置以下参数：

### 必需配置
```bash
NAPCAT_URL="http://localhost:3000"           # NapCat API地址
GEMINI_API_URL="YOUR_GEMINI_API_ENDPOINT"    # Gemini API端点
GEMINI_API_KEY="YOUR_API_KEY"                # Gemini API密钥
GROUP_ID="YOUR_GROUP_ID"                     # 目标QQ群号
BOT_QQ="YOUR_BOT_QQ"                         # 机器人QQ号
```

### 配置方法

1. **Shell/AWK/Factor版本**: 直接编辑文件中的常量定义
2. **Make版本**: 修改Makefile顶部的变量
3. **Excel版本**: 在Excel工作表中设置配置单元格

## 机器人特性

### 个性设定
- 名字：楠楠
- 年龄：23岁
- 性格：网友风格，爱吐槽，简洁直接
- 回复风格：20字以内，多用吐槽少用解释

### 工作流程
1. 持续监听群消息
2. 检测新消息（排除自己的消息）
3. 分析对话上下文
4. 决定是否需要回复
5. 生成个性化回复或选择保持沉默

### AI决策机制
机器人使用function calling机制：
- `send_group_message`: 发送消息到群
- `end`: 选择不回复（话题无聊时）

## 项目结构

```
.
├── simple-bot.sh              # Bash实现
├── simple-bot.awk             # AWK实现
├── simple-bot.factor          # Factor实现
├── Makefile                   # Make实现
├── Excel_QQ_Bot_VBA.txt       # VBA实现
└── README.md                  # 项目文档
```

## 注意事项

⚠️ **隐私安全**
- 本项目已移除所有敏感信息
- 使用前请配置你自己的API密钥和群组信息
- 不要将配置信息提交到公共代码仓库

⚠️ **使用限制**
- 需要合法的QQ账号和群组权限
- 遵守相关平台的使用条款
- 注意API调用频率限制

⚠️ **技术提醒**
- NapCat需要单独安装和配置
- 部分系统可能需要调整时间格式化命令
- Excel版本需要启用宏功能

## 开发说明

这个项目主要用于：
- 学习不同编程语言的特性
- 理解相同逻辑的不同实现方式
- 探索各种编程范式（过程式、函数式、声明式等）
- AI聊天机器人开发实践

## 许可证

本项目基于 [MIT License](LICENSE) 开源许可证发布。

你可以自由地：
- 使用、复制、修改、合并、发布、分发本软件
- 在任何项目中使用（包括商业项目）

唯一的要求是在所有副本中保留版权声明和许可证声明。

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=mifanTeddy/one-file-run-qq-agent&type=Date)](https://www.star-history.com/#mifanTeddy/one-file-run-qq-agent&Date)

## 贡献

欢迎提交Issue和Pull Request，特别是：
- 新的编程语言实现
- 性能优化
- 功能增强
- 文档改进

如果这个项目对你有帮助，请考虑给个 ⭐ Star 支持一下！

---

*注：使用本项目请遵守相关法律法规和平台规则*