// Text of the privacy policy and support pages, in English and Chinese.
// Keep both languages in step, and keep every statement true for what the app and
// its providers actually do. Update `updated` whenever the policy changes.

export type Lang = "en" | "zh";

export type Section = {
  heading: string;
  paragraphs?: string[];
  items?: string[];
};

export type Page = {
  title: string;
  updated: string;
  intro: string;
  sections: Section[];
  otherLanguage: { label: string; href: string };
};

export const CONTACT_EMAIL = "support@ironsage.app";

export const privacy: Record<Lang, Page> = {
  en: {
    title: "Privacy policy",
    updated: "Last updated October 26, 2026",
    intro:
      "IronSage is a strength-training log for iPhone with an optional AI coach. It is run by an individual developer. This page explains what data IronSage keeps, why, who helps process it, and how you can delete it.",
    otherLanguage: { label: "中文", href: "/privacy/zh" },
    sections: [
      {
        heading: "What IronSage keeps",
        items: [
          "Account: your email address and the ID of your sign-in account. Sign-in uses an email code, Google or Apple, so IronSage never sees a password.",
          "Profile: birthday, height, gender, where you train, units, experience, goal and training days per week. All are optional except units.",
          "Training: your workouts, exercises, sets, reps, weights, notes, templates and the exercises you create.",
          "Body measurements you enter or allow from Apple Health: weight, body fat and girth measurements.",
          "Apple Health data, only if you allow it: sleep time and sleep stages, heart rate variability, resting heart rate, and average and maximum heart rate during workouts. IronSage stores daily summaries, not the raw readings.",
          "AI coach, if you turn it on: the suggestions and weekly summaries it writes, each with the data it was based on.",
          "Subscription, if you subscribe: Apple's record of the purchase, meaning the product, Apple's transaction ID, the dates, any offer or promotion code used, and whether it renewed, expired or was refunded. IronSage never sees your payment details.",
          "Server logs: when requests reach the IronSage API and any errors they cause, kept for 30 days to fix problems and keep the service secure. The website's host keeps its own short-lived request logs, which include IP addresses.",
        ],
      },
      {
        heading: "What IronSage does not do",
        items: [
          "It shows no ads and does not sell or rent your data.",
          "It does not use Apple Health data for advertising, marketing or data mining, and does not share it with data brokers.",
          "It contains no third-party analytics or tracking code.",
        ],
      },
      {
        heading: "How your data is used",
        items: [
          "To run the app: save your training, show your history and progress, and keep your devices in sync.",
          "For the AI coach, only if you turn it on (see below).",
          "To answer you when you contact support, and to find and fix problems.",
        ],
      },
      {
        heading: "The AI coach",
        paragraphs: [
          "The AI coach is optional and off until you turn it on. It suggests your next session and, every Monday, writes a summary of your past week. For each, IronSage sends Anthropic, the company behind the Claude AI model, only what it needs: your recent sets for the exercises involved, or for the weekly summary the week's sets per muscle, records and lifts that stalled; your experience, goal, units and language; and daily summaries of sleep, heart rate variability and resting heart rate. Your email address and name are not sent.",
          "Anthropic processes this data to produce the suggestion or summary for IronSage. Its handling of the data is described in Anthropic's privacy policy at anthropic.com/legal/privacy. Each suggestion and summary is saved in your account together with the data it was based on, so you can see why it was made.",
          "You can turn the AI coach off at any time in Settings. IronSage then stops sending data to Anthropic.",
        ],
      },
      {
        heading: "Who helps run IronSage",
        paragraphs: ["These companies process data on IronSage's behalf, only to provide their service:"],
        items: [
          "Clerk: sign-in and your sign-in account.",
          "Amazon Web Services: runs the IronSage API (United States).",
          "Neon: hosts the database (United States).",
          "Vercel: hosts the ironsage.app website.",
          "Cloudflare: domain name and email forwarding for support.",
          "Apple: App Store, subscriptions and payments. Apple Health data stays under your control on your iPhone until you allow IronSage to read it.",
          "Anthropic: the AI coach, only while it is turned on.",
        ],
      },
      {
        heading: "Where your data is stored",
        paragraphs: [
          "IronSage's servers and database are in the United States. If you use IronSage from another country, your data is transferred there.",
        ],
      },
      {
        heading: "How long data is kept, and deleting it",
        items: [
          "Your data is kept while you have an account.",
          "Delete your account in the app under Settings, or at ironsage.app/account. This immediately deletes your profile, training, measurements, health summaries, AI suggestions and weekly summaries from the database, and your sign-in account.",
          "If you subscribed, Apple's record of that purchase (product, transaction ID and dates, without your name or email) is kept but no longer linked to you, so the same purchase can't be claimed by another account. Deleting your account doesn't cancel the subscription; cancel it with Apple.",
          "Database backups expire within 30 days, and server logs after 30 days.",
        ],
      },
      {
        heading: "Your choices",
        items: [
          "See and change your data in the app at any time.",
          "Stop Apple Health access in the iPhone Settings app, under Health, Data Access & Devices, IronSage.",
          "Turn off the AI coach in Settings.",
          `Ask for a copy of your data, or about any other privacy right you have where you live, by emailing ${CONTACT_EMAIL}. You will get an answer within 30 days.`,
        ],
      },
      {
        heading: "Health information",
        paragraphs: [
          "IronSage is a training log and coach for healthy adults, not a medical service. Its suggestions are not medical advice.",
        ],
      },
      {
        heading: "Children",
        paragraphs: ["IronSage is not meant for anyone under 16 and does not knowingly collect their data."],
      },
      {
        heading: "Changes and contact",
        paragraphs: [
          "If this policy changes, the date at the top changes too, and important changes are announced in the app before they take effect.",
          `Questions: ${CONTACT_EMAIL}.`,
        ],
      },
    ],
  },
  zh: {
    title: "隐私政策",
    updated: "最后更新：2026 年 10 月 26 日",
    intro:
      "IronSage 是一款 iPhone 力量训练记录 App，附带可选的 AI 教练，由一位个人开发者运营。本页说明 IronSage 保存哪些数据、为什么保存、由谁协助处理，以及如何删除。",
    otherLanguage: { label: "English", href: "/privacy" },
    sections: [
      {
        heading: "IronSage 保存哪些数据",
        items: [
          "账号：你的邮箱地址和登录账号的 ID。登录方式是邮箱验证码、Google 或 Apple，IronSage 不会接触到任何密码。",
          "档案：生日、身高、性别、训练地点、单位、训练经验、目标和每周训练天数。除单位外都可以不填。",
          "训练：你的训练记录、动作、组数、次数、重量、备注、训练模板，以及你自建的动作。",
          "你手动输入或允许从 Apple 健康读取的身体数据：体重、体脂和围度。",
          "Apple 健康数据，仅在你允许时读取：睡眠时长和睡眠阶段、心率变异性、静息心率，以及训练时的平均和最高心率。IronSage 只保存每天的汇总，不保存原始读数。",
          "AI 教练，仅在你开启后：它写的建议和每周总结，以及每条所依据的数据。",
          "订阅，仅在你订阅后：Apple 提供的购买记录，包括产品、Apple 的交易编号、日期、使用过的优惠或促销码，以及续订、到期或退款的状态。IronSage 不会接触到你的付款信息。",
          "服务器日志：请求到达 IronSage 接口的时间，以及引发的错误，保存 30 天，用于排查问题和保障安全。网站的托管服务商会保留自己的短期访问日志，其中包含 IP 地址。",
        ],
      },
      {
        heading: "IronSage 不会做的事",
        items: [
          "不展示广告，不出售或出租你的数据。",
          "不把 Apple 健康数据用于广告、营销或数据挖掘，也不提供给数据经纪商。",
          "不包含任何第三方统计或追踪代码。",
        ],
      },
      {
        heading: "数据的用途",
        items: [
          "提供 App 的功能：保存训练、显示历史和进度、在你的设备之间同步。",
          "提供 AI 教练功能，仅在你开启后（见下文）。",
          "回复你的客服邮件，以及发现和修复问题。",
        ],
      },
      {
        heading: "AI 教练",
        paragraphs: [
          "AI 教练是可选功能，默认关闭，需要你主动开启。它会建议你下一次怎么练，并在每周一总结你上一周的训练。每次 IronSage 只把需要的数据发给 Anthropic（Claude AI 模型背后的公司）：相关动作最近的训练组，或者在每周总结里，这一周每块肌肉的组数、新纪录和停滞的动作；你的训练经验、目标、单位和语言；以及睡眠、心率变异性和静息心率的每日汇总。不会发送你的邮箱和姓名。",
          "Anthropic 处理这些数据，为 IronSage 生成建议或总结。它如何处理数据，请见 Anthropic 的隐私政策：anthropic.com/legal/privacy。每条建议和总结会和它所依据的数据一起保存在你的账号里，方便你查看理由。",
          "你可以随时在设置里关闭 AI 教练，之后 IronSage 不再向 Anthropic 发送数据。",
        ],
      },
      {
        heading: "协助运营 IronSage 的服务商",
        paragraphs: ["以下公司代表 IronSage 处理数据，仅用于提供它们的服务："],
        items: [
          "Clerk：登录和你的登录账号。",
          "Amazon Web Services：运行 IronSage 接口（美国）。",
          "Neon：托管数据库（美国）。",
          "Vercel：托管 ironsage.app 网站。",
          "Cloudflare：域名，以及客服邮箱的邮件转发。",
          "Apple：App Store、订阅和付款。在你允许 IronSage 读取之前，Apple 健康数据只保存在你的 iPhone 上，由你掌控。",
          "Anthropic：AI 教练，仅在开启期间。",
        ],
      },
      {
        heading: "数据存放在哪里",
        paragraphs: ["IronSage 的服务器和数据库位于美国。如果你在其他国家或地区使用 IronSage，你的数据会被传输到美国。"],
      },
      {
        heading: "保存多久，以及如何删除",
        items: [
          "在你的账号存在期间，数据会一直保存。",
          "在 App 的设置里，或在 ironsage.app/account 删除账号。删除后会立即从数据库中删除你的档案、训练记录、身体数据、健康汇总、AI 建议和每周总结，并删除你的登录账号。",
          "如果你订阅过，Apple 提供的那次购买记录（产品、交易编号和日期，不含你的姓名和邮箱）会保留，但不再与你关联，以免同一笔购买被其他账号重复使用。删除账号不会取消订阅，请在 Apple 那里取消。",
          "数据库备份在 30 天内过期，服务器日志保存 30 天。",
        ],
      },
      {
        heading: "你可以做的选择",
        items: [
          "随时在 App 里查看和修改你的数据。",
          "在 iPhone 的“设置”App 中，依次进入 健康 › 数据访问与设备 › IronSage，停止 Apple 健康的访问权限。",
          "在设置里关闭 AI 教练。",
          `如需获取你的数据副本，或行使你所在地法律赋予你的其他隐私权利，请发邮件到 ${CONTACT_EMAIL}，我们会在 30 天内回复。`,
        ],
      },
      {
        heading: "健康信息",
        paragraphs: ["IronSage 是面向健康成年人的训练记录和教练工具，不是医疗服务。它给出的建议不构成医疗建议。"],
      },
      {
        heading: "未成年人",
        paragraphs: ["IronSage 不面向 16 岁以下的用户，也不会有意收集他们的数据。"],
      },
      {
        heading: "政策变更和联系方式",
        paragraphs: [
          "本政策如有修改，页首的日期会同步更新；重要变更会在生效前于 App 内提前告知。",
          `有任何问题请联系：${CONTACT_EMAIL}。`,
        ],
      },
    ],
  },
};

export const support: Record<Lang, Page> = {
  en: {
    title: "Support",
    updated: "",
    intro: `Email ${CONTACT_EMAIL} and include the email address you sign in with. You will usually get an answer within two working days.`,
    otherLanguage: { label: "中文", href: "/support/zh" },
    sections: [
      {
        heading: "Delete your account",
        paragraphs: [
          "In the app, go to Settings and choose Delete account, or sign in at ironsage.app/account. This deletes your data and cannot be undone; only Apple's record of a subscription purchase is kept, unlinked from you (see the privacy policy). Cancel an active subscription separately (see below).",
        ],
      },
      {
        heading: "Cancel a subscription",
        paragraphs: [
          "Subscriptions are handled by Apple. On your iPhone, open Settings, tap your name, then Subscriptions, and choose IronSage.",
        ],
      },
      {
        heading: "Stop Apple Health access",
        paragraphs: [
          "Open the Settings app, then Health, Data Access & Devices, IronSage, and turn off the categories you no longer want to share.",
        ],
      },
      {
        heading: "Get a copy of your data",
        paragraphs: [`Email ${CONTACT_EMAIL} from the address you sign in with.`],
      },
    ],
  },
  zh: {
    title: "客服支持",
    updated: "",
    intro: `请发邮件到 ${CONTACT_EMAIL}，并注明你登录时使用的邮箱。通常两个工作日内回复。`,
    otherLanguage: { label: "English", href: "/support" },
    sections: [
      {
        heading: "删除账号",
        paragraphs: [
          "在 App 中进入设置，选择“删除账号”；或登录 ironsage.app/account 删除。删除会清除你的数据，且无法恢复；只有 Apple 提供的订阅购买记录会保留，并且不再与你关联（见隐私政策）。如有进行中的订阅，需要另外取消（见下文）。",
        ],
      },
      {
        heading: "取消订阅",
        paragraphs: ["订阅由 Apple 管理。在 iPhone 上打开“设置”，点你的名字，再点“订阅”，选择 IronSage。"],
      },
      {
        heading: "停止 Apple 健康访问",
        paragraphs: ["打开“设置”App，依次进入 健康 › 数据访问与设备 › IronSage，关闭不想再共享的类别。"],
      },
      {
        heading: "获取数据副本",
        paragraphs: [`用你登录时使用的邮箱发邮件到 ${CONTACT_EMAIL}。`],
      },
    ],
  },
};
