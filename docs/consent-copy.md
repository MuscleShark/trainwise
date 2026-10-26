# Consent copy for the iPhone app

Text for the screens where IronSage asks for Apple Health access and for permission to send data to the AI coach, in English and Simplified Chinese. The iPhone app uses these strings as written; change them here first, and keep them consistent with the [privacy policy](../frontend/app/components/legal-content.ts).

Rules the copy follows:

- Say exactly which data is read or sent, in plain words, before the user decides.
- The choice is real: "Not now" keeps every free feature working.
- Button labels name the action ("Allow Apple Health", "Turn on AI coach"), never "OK".
- The same terms everywhere: "Apple Health" / "Apple 健康", "AI coach" / "AI 教练", "daily summaries" / "每日汇总".

## 1. Before the Apple Health prompt

Shown once, before iOS's own permission sheet (M2).

| | English | 中文 |
|---|---|---|
| Title | Use your Apple Health data | 使用你的 Apple 健康数据 |
| Body | IronSage can read your sleep, heart rate variability, resting heart rate and workout heart rate, and save your workouts to Apple Health. You'll see progress and recovery side by side. | IronSage 可以读取你的睡眠、心率变异性、静息心率和训练心率，并把训练记录保存到 Apple 健康，让你把进步和恢复情况放在一起看。 |
| Note | Only daily summaries are stored, never the raw readings. You can change this any time in the Settings app under Health. | 只保存每日汇总，不保存原始读数。你可以随时在“设置”App 的“健康”中更改。 |
| Primary button | Allow Apple Health | 允许访问 Apple 健康 |
| Secondary button | Not now | 暂不 |

## 2. Info.plist permission strings

iOS shows these inside its permission sheet. Keep them short; they must explain the purpose (App Review checks this).

| Key | English | 中文 |
|---|---|---|
| `NSHealthShareUsageDescription` | IronSage reads sleep, heart rate variability, resting heart rate and workout heart rate to show your recovery and tailor training suggestions. | IronSage 读取睡眠、心率变异性、静息心率和训练心率，用来显示你的恢复情况并调整训练建议。 |
| `NSHealthUpdateUsageDescription` | IronSage saves your strength workouts to Apple Health. | IronSage 会把你的力量训练记录保存到 Apple 健康。 |

## 3. Turning on the AI coach

Shown when a subscriber turns on the AI coach for the first time (M3). Nothing is sent to Anthropic before the user taps the primary button. The app then tells the server the coach is on (`PUT /v1/coach/settings`), so the weekly summary is written only for users who agreed, and stops when they turn the coach off (once the phone has synced) or sign out.

| | English | 中文 |
|---|---|---|
| Title | Turn on the AI coach? | 开启 AI 教练？ |
| Body | To suggest your next weights and reps and write your weekly summary, IronSage sends this to Anthropic, the company that makes the Claude AI model: | 为了建议你下次的重量和次数并撰写每周总结，IronSage 会把以下数据发给 Anthropic（Claude AI 模型背后的公司）： |
| List item 1 | Your recent sets, and each week's sets per muscle and records | 你最近的训练组，以及每周各肌群的组数和个人纪录 |
| List item 2 | Your experience, goal and units | 你的训练经验、目标和单位 |
| List item 3 | Daily summaries of sleep, heart rate variability and resting heart rate | 睡眠、心率变异性和静息心率的每日汇总 |
| Not sent | Your name and email address are never sent. | 不会发送你的姓名和邮箱地址。 |
| Note | Every suggestion shows the data it used. You can turn the AI coach off in Settings at any time. | 每条建议都会显示它所依据的数据。你可以随时在设置中关闭 AI 教练。 |
| Link | Privacy policy | 隐私政策 |
| Primary button | Turn on AI coach | 开启 AI 教练 |
| Secondary button | Not now | 暂不 |

## 4. AI coach in Settings

| | English | 中文 |
|---|---|---|
| Toggle label | AI coach | AI 教练 |
| Toggle footnote (on) | Sends your recent training and daily health summaries to Anthropic to prepare suggestions. | 会把你最近的训练和每日健康汇总发给 Anthropic，用于生成建议。 |
| Toggle footnote (off) | Nothing is sent to Anthropic. | 不会向 Anthropic 发送任何数据。 |
| Confirm turning off: title | Turn off the AI coach? | 关闭 AI 教练？ |
| Confirm turning off: body | You'll stop getting suggestions, and IronSage stops sending data to Anthropic. Past suggestions stay in your history. | 你将不再收到建议，IronSage 也会停止向 Anthropic 发送数据。以前的建议仍保留在历史记录中。 |
| Confirm turning off: buttons | Turn off / Keep on | 关闭 / 保持开启 |

## 5. Health disclaimer

Shown under every AI suggestion, small text.

| English | 中文 |
|---|---|
| Training guidance, not medical advice. Stop if something hurts. | 仅为训练建议，不构成医疗建议。如有疼痛请停止训练。 |
