// ===== Field definitions =====
let FIELDS = [];
const GROUP_ORDER = ['basic','world','combat','player','pal','items','building','guild','permissions','network','automation','logging','runtime','engine','advanced'];
const GROUP_LABELS = {
  zh: {
    all:'全部分组', basic:'基础与容量', world:'世界与难度', combat:'战斗与 PvP',
    player:'玩家与生存', pal:'帕鲁', items:'物品与掉落', building:'据点与建筑',
    guild:'公会与多人', permissions:'功能与权限', network:'连接与 API',
    automation:'备份与自动化', logging:'日志与通知', runtime:'容器与启动',
    engine:'Engine.ini 性能', advanced:'其他高级项'
  },
  en: {
    all:'All groups', basic:'Basics & Capacity', world:'World & Difficulty', combat:'Combat & PvP',
    player:'Player & Survival', pal:'Pals', items:'Items & Drops', building:'Bases & Building',
    guild:'Guild & Multiplayer', permissions:'Features & Permissions', network:'Connectivity & APIs',
    automation:'Backup & Automation', logging:'Logging & Notifications', runtime:'Container & Startup',
    engine:'Engine.ini Performance', advanced:'Other Advanced'
  }
};
const ZH_LABELS = {
  SERVER_NAME:'服务器名称', SERVER_DESCRIPTION:'服务器描述', PLAYERS:'服务器玩家上限',
  COOP_PLAYER_MAX_NUM:'合作队伍人数上限', SERVER_PASSWORD:'服务器密码', ADMIN_PASSWORD:'管理员密码',
  EXP_RATE:'经验倍率', PAL_CAPTURE_RATE:'捕捉率', PAL_SPAWN_NUM_RATE:'帕鲁生成数量',
  WORK_SPEED_RATE:'工作速度', COLLECTION_DROP_RATE:'采集掉落倍率', ENEMY_DROP_ITEM_RATE:'敌人掉落倍率',
  DAYTIME_SPEEDRATE:'白天时间流速', NIGHTTIME_SPEEDRATE:'夜晚时间流速',
  PAL_EGG_DEFAULT_HATCHING_TIME:'孵蛋时间倍率', AUTO_SAVE_SPAN:'游戏自动保存间隔',
  SUPPLY_DROP_SPAN:'空投间隔', PLAYER_DAMAGE_RATE_ATTACK:'玩家攻击伤害',
  PLAYER_DAMAGE_RATE_DEFENSE:'玩家受到伤害', PAL_DAMAGE_RATE_ATTACK:'帕鲁攻击伤害',
  PAL_DAMAGE_RATE_DEFENSE:'帕鲁受到伤害', DEATH_PENALTY:'死亡惩罚',
  ENABLE_PLAYER_TO_PLAYER_DAMAGE:'允许玩家互相伤害', ENABLE_FRIENDLY_FIRE:'友军伤害',
  IS_PVP:'PvP 模式', ENABLE_INVADER_ENEMY:'入侵事件', PLAYER_STOMACH_DECREASE_RATE:'玩家饥饿速率',
  PLAYER_STAMINA_DECREASE_RATE:'玩家耐力消耗', PLAYER_AUTO_HP_REGEN_RATE:'玩家自动回血',
  PLAYER_AUTO_HP_REGEN_RATE_IN_SLEEP:'玩家睡眠回血', PAL_STOMACH_DECREASE_RATE:'帕鲁饥饿速率',
  PAL_STAMINA_DECREASE_RATE:'帕鲁耐力消耗', PAL_AUTO_HP_REGEN_RATE:'帕鲁自动回血',
  PAL_AUTO_HP_REGEN_RATE_IN_SLEEP:'帕鲁睡眠回血', BUILD_OBJECT_HP_RATE:'建筑生命值',
  BUILD_OBJECT_DAMAGE_RATE:'建筑受到伤害', BUILD_OBJECT_DETERIORATION_DAMAGE_RATE:'建筑腐坏速率',
  BASE_CAMP_MAX_NUM:'全服据点上限', BASE_CAMP_WORKER_MAX_NUM:'据点工作帕鲁上限',
  DROP_ITEM_MAX_NUM:'地面掉落物上限', GUILD_PLAYER_MAX_NUM:'公会玩家上限',
  ENABLE_FAST_TRAVEL:'允许快速旅行', SHOW_PLAYER_LIST:'显示玩家列表', DIFFICULTY:'难度预设',
  RANDOMIZER_TYPE:'随机化类型', RANDOMIZER_SEED:'随机化种子', HARDCORE:'硬核模式',
  PAL_LOST:'硬核死亡丢失帕鲁', CROSSPLAY_PLATFORMS:'跨平台列表', ALLOW_CLIENT_MOD:'允许客户端 Mod',
  DISABLE_GENERATE_ENGINE:'禁用 Engine.ini 生成', UPDATE_ON_BOOT:'启动时更新',
  BACKUP_ENABLED:'启用定时备份', DELETE_OLD_BACKUPS:'自动删除旧备份',
  OLD_BACKUP_DAYS:'备份保留天数', AUTO_UPDATE_ENABLED:'启用定时自动更新',
  AUTO_REBOOT_ENABLED:'启用定时重启', AUTO_PAUSE_ENABLED:'无人时自动暂停',
  ENABLE_PLAYER_LOGGING:'记录玩家进出', LOG_FILTER_ENABLED:'启用日志过滤',
  LOG_LEVEL:'容器日志级别', LOG_FORMAT_TYPE:'游戏日志格式', PORT:'游戏监听端口',
  PUBLIC_PORT:'对外公布端口', PUBLIC_IP:'对外公布 IP', RCON_ENABLED:'启用 RCON',
  RCON_PORT:'RCON 端口', REST_API_ENABLED:'启用 REST API', REST_API_PORT:'REST API 端口',
  COMMUNITY:'注册社区服务器', MULTITHREADING:'旧版多线程启动参数',
  ENABLE_PERF_THREADING_ARGS:'启用性能线程参数', WORKER_THREADS_SERVER:'服务端工作线程数',
  PALWORLD_ALLOW_NEGATIVE_DELTA_TIME:'允许负 Delta Time', PUID:'容器用户 UID', PGID:'容器用户组 GID',
  TZ:'时区', DISCORD_WEBHOOK_URL:'Discord 默认 Webhook', USE_DEPOT_DOWNLOADER:'使用 DepotDownloader',
  INSTALL_BETA_INSIDER:'安装 Insider 测试版本', ENABLE_GAMEDATA_API:'启用游戏数据 API',
  ENABLE_VOICE_CHAT:'启用语音聊天', VOICE_CHAT_MAX_VOLUME_DISTANCE:'语音最大音量距离',
  VOICE_CHAT_ZERO_VOLUME_DISTANCE:'语音零音量距离', USE_BACKUP_SAVE_DATA:'启用游戏内存档备份',
  CROSSPLAY_PLATFORMS:'跨平台列表', BAN_LIST_URL:'封禁名单 URL', REGION:'服务器区域'
};
const ZH_TOKENS = {
  ALLOW:'允许', ENABLE:'启用', DISABLE:'禁用', PLAYER:'玩家', PLAYERS:'玩家', PAL:'帕鲁',
  SERVER:'服务器', GUILD:'公会', BASE:'据点', CAMP:'营地', BUILDING:'建筑', BUILD:'建筑',
  ITEM:'物品', DROP:'掉落', DAMAGE:'伤害', RATE:'倍率', SPEED:'速度', TIME:'时间',
  AUTO:'自动', BACKUP:'备份', UPDATE:'更新', REBOOT:'重启', PAUSE:'暂停', LOG:'日志',
  MESSAGE:'消息', ENABLED:'启用', URL:'URL', PORT:'端口', PUBLIC:'公开', MAX:'最大',
  NUM:'数量', COUNT:'数量', INTERVAL:'间隔', MINUTES:'分钟', SECONDS:'秒', HOURS:'小时',
  DAYS:'天', HEALTH:'生命值', ATTACK:'攻击', STAMINA:'耐力', WEIGHT:'负重', WORK:'工作',
  VOICE:'语音', CHAT:'聊天', DISPLAY:'显示', WORLD:'世界', MAP:'地图', RESPAWN:'重生',
  PENALTY:'惩罚', TECHNOLOGY:'科技', RANDOMIZER:'随机化', SEED:'种子', LEVEL:'等级',
  FRIENDLY:'友军', FIRE:'伤害', INVADER:'入侵', AIM:'瞄准', ASSIST:'辅助', KEYBOARD:'键盘',
  PAD:'手柄', SLEEP:'睡眠', REGEN:'恢复', STOMACH:'饥饿', COLLECTION:'采集',
  OBJECT:'对象', ALIVE:'存留', RESET:'重置', ONLINE:'在线', OFFLINE:'离线',
  FIXED:'固定', FRAME:'帧', TICK:'Tick', INTERNET:'互联网', LAN:'局域网',
  CLIENT:'客户端', CONFIGURED:'配置', SMOOTH:'平滑', LOWER:'下限', UPPER:'上限',
  MASTER:'会长', TRANSFER:'转移', CHECK:'检查', THRESHOLD:'阈值', DESCRIPTION:'描述',
  PASSWORD:'密码', NAME:'名称', DEFAULT:'默认', TRUE:'是', FALSE:'否',
  VOLUME:'音量', DISTANCE:'距离', ZERO:'零', FORMAT:'格式', TYPE:'类型',
  FORCE:'强制', DIRTY:'脏标记', POLL:'轮询', PERIOD:'周期', ACTION:'动作'
};
function settingLabel(field) {
  if (currentLang === 'en') return field.labelEn || titleCaseKey(field.key);
  if (field.labelZh) return field.labelZh;
  if (ZH_LABELS[field.key]) return ZH_LABELS[field.key];
  return field.key.split('_').map(token => ZH_TOKENS[token] || token.toLowerCase()).join(' · ');
}
function titleCaseKey(key) {
  return key.toLowerCase().split('_').map(s => s.charAt(0).toUpperCase() + s.slice(1)).join(' ');
}
/*
const LEGACY_FIELDS = [
  { group: "基础", key: "SERVER_NAME", label: "服务器名称", type: "text", default: "Palworld-Docker" },
  { group: "基础", key: "SERVER_DESCRIPTION", label: "服务器描述", type: "text", default: "Private Server" },
  { group: "基础", key: "PLAYERS", label: "服务器玩家上限", type: "number", min: 1, max: 32, default: 8 },
  { group: "基础", key: "COOP_PLAYER_MAX_NUM", label: "合作队伍人数上限", type: "number", min: 1, max: 32, default: 8 },
  { group: "基础", key: "SERVER_PASSWORD", label: "服务器密码", type: "password", default: "", hint: "留空 = 无密码" },
  { group: "游戏速率", key: "EXP_RATE", label: "经验倍率", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0 },
  { group: "游戏速率", key: "PAL_CAPTURE_RATE", label: "捕捉率", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0 },
  { group: "游戏速率", key: "PAL_SPAWN_NUM_RATE", label: "帕鲁生成数量", type: "number", min: 0.1, max: 20, step: 0.1, default: 1.0 },
  { group: "游戏速率", key: "WORK_SPEED_RATE", label: "工作速度", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0 },
  { group: "游戏速率", key: "COLLECTION_DROP_RATE", label: "采集掉落倍率", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0 },
  { group: "游戏速率", key: "ENEMY_DROP_ITEM_RATE", label: "敌人掉落倍率", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0 },
  { group: "时间", key: "DAYTIME_SPEEDRATE", label: "白天时间流速", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0, hint: "0.5 ≈ 白天持续时间加倍" },
  { group: "时间", key: "NIGHTTIME_SPEEDRATE", label: "夜晚时间流速", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0 },
  { group: "时间", key: "PAL_EGG_DEFAULT_HATCHING_TIME", label: "孵蛋时间倍率", type: "number", min: 0, max: 240, step: 0.1, default: 1.0, hint: "越小越快" },
  { group: "时间", key: "AUTO_SAVE_SPAN", label: "自动保存间隔（秒）", type: "number", min: 10, max: 3600, default: 30 },
  { group: "时间", key: "SUPPLY_DROP_SPAN", label: "空投间隔（分钟）", type: "number", min: 1, max: 10080, default: 180 },
  { group: "战斗", key: "PLAYER_DAMAGE_RATE_ATTACK", label: "玩家攻击伤害", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0 },
  { group: "战斗", key: "PLAYER_DAMAGE_RATE_DEFENSE", label: "玩家受伤倍率", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0 },
  { group: "战斗", key: "PAL_DAMAGE_RATE_ATTACK", label: "帕鲁攻击伤害", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0 },
  { group: "战斗", key: "PAL_DAMAGE_RATE_DEFENSE", label: "帕鲁受伤倍率", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0 },
  { group: "战斗", key: "DEATH_PENALTY", label: "死亡惩罚", type: "select", options: ["None","Item","ItemAndEquipment","All"], default: "None" },
  { group: "战斗", key: "ENABLE_PLAYER_TO_PLAYER_DAMAGE", label: "玩家间伤害", type: "checkbox", default: false },
  { group: "战斗", key: "ENABLE_FRIENDLY_FIRE", label: "友军伤害", type: "checkbox", default: false },
  { group: "战斗", key: "IS_PVP", label: "PvP 模式", type: "checkbox", default: false },
  { group: "战斗", key: "ENABLE_INVADER_ENEMY", label: "入侵者敌人", type: "checkbox", default: true },
  { group: "生存", key: "PLAYER_STOMACH_DECREASE_RATE", label: "玩家饥饿速率", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0 },
  { group: "生存", key: "PLAYER_STAMINA_DECREASE_RATE", label: "玩家耐力消耗", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0 },
  { group: "生存", key: "PLAYER_AUTO_HP_REGEN_RATE", label: "玩家自动回血", type: "number", min: 0, max: 100, step: 0.1, default: 1.0 },
  { group: "生存", key: "PLAYER_AUTO_HP_REGEN_RATE_IN_SLEEP", label: "玩家睡眠回血", type: "number", min: 0, max: 100, step: 0.1, default: 1.0 },
  { group: "生存", key: "PAL_STOMACH_DECREASE_RATE", label: "帕鲁饥饿速率", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0 },
  { group: "生存", key: "PAL_STAMINA_DECREASE_RATE", label: "帕鲁耐力消耗", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0 },
  { group: "生存", key: "PAL_AUTO_HP_REGEN_RATE", label: "帕鲁自动回血", type: "number", min: 0, max: 100, step: 0.1, default: 1.0 },
  { group: "生存", key: "PAL_AUTO_HP_REGEN_RATE_IN_SLEEP", label: "帕鲁睡眠回血", type: "number", min: 0, max: 100, step: 0.1, default: 1.0 },
  { group: "建筑", key: "BUILD_OBJECT_HP_RATE", label: "建筑血量", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0 },
  { group: "建筑", key: "BUILD_OBJECT_DAMAGE_RATE", label: "建筑受伤倍率", type: "number", min: 0.1, max: 100, step: 0.1, default: 1.0 },
  { group: "建筑", key: "BUILD_OBJECT_DETERIORATION_DAMAGE_RATE", label: "建筑腐坏速率", type: "number", min: 0, max: 100, step: 0.1, default: 1.0 },
  { group: "建筑", key: "BASE_CAMP_MAX_NUM", label: "据点上限", type: "number", min: 1, max: 1024, default: 128 },
  { group: "建筑", key: "BASE_CAMP_WORKER_MAX_NUM", label: "据点帕鲁上限", type: "number", min: 1, max: 100, default: 15 },
  { group: "其他", key: "DROP_ITEM_MAX_NUM", label: "掉落物上限", type: "number", min: 0, max: 100000, default: 3000 },
  { group: "其他", key: "GUILD_PLAYER_MAX_NUM", label: "公会玩家上限", type: "number", min: 1, max: 100, default: 20 },
  { group: "其他", key: "ENABLE_FAST_TRAVEL", label: "启用快速旅行", type: "checkbox", default: true },
  { group: "其他", key: "SHOW_PLAYER_LIST", label: "显示玩家列表", type: "checkbox", default: false },
];
*/

const RCON_CMDS = [
  { cmd: 'showplayers', key: 'showplayers', risk: 'safe' },
  { cmd: 'info', key: 'info', risk: 'safe' },
  { cmd: 'save', key: 'save', risk: 'safe' },
  { cmd: 'broadcast <message>', key: 'broadcast', risk: 'safe' },
  { cmd: 'kickplayer <steamid>', key: 'kickplayer', risk: 'player' },
  { cmd: 'banplayer <steamid>', key: 'banplayer', risk: 'player' },
  { cmd: 'unbanplayer <steamid>', key: 'unbanplayer', risk: 'player' },
  { cmd: 'teleporttoplayer <steamid>', key: 'teleporttoplayer', risk: 'player' },
  { cmd: 'teleporttome <steamid>', key: 'teleporttome', risk: 'player' },
  { cmd: 'togglespectate', key: 'togglespectate', risk: 'player' },
  { cmd: 'shutdown 60 <message>', key: 'shutdown', risk: 'danger' },
  { cmd: 'doexit', key: 'doexit', risk: 'danger' },
];

// ===== State =====
let envValues = {};
let envDraft = {};
let envModified = new Set();
let explicitSettings = new Set();
let configuredSecrets = new Set();
let settingsExclusions = [];
let dashboardState = null;
let logAutoRefreshTimer = null;
let currentLang = 'zh';
let modState = null;
// Raw player identifiers are intentionally kept only in memory. The player
// table receives opaque candidate keys so privacy masking does not leak an ID
// into an HTML attribute, log, or persisted browser state.
let playerCommandCandidates = new Map();

const PLAYER_COMMAND_ID_FIELDS = [
  { kind: 'steamId', key: 'rcon.playerPicker.steamId', fields: ['steamId', 'steamid', 'steam_id'] },
  { kind: 'playerUid', key: 'rcon.playerPicker.playerUid', fields: ['playerUserId', 'playeruid', 'playerUid', 'player_uid', 'userId', 'userid'] }
];

// ===== i18n =====
const I18N = {
  zh: {
    'status.connecting': '连接中…',
    'status.online': '在线',
    'status.starting': '启动中',
    'status.stopped': '已停止',
    'status.absent': '未创建',
    'status.restarting': '重启中',
    'status.unknown': '未知',
    'status.offline': '离线',
    'meta.uptime': '运行时长',
    'meta.port': '端口',
    'accessibility.runtimePill': '当前运行时',
    'accessibility.languageToggle': '切换语言',
    'accessibility.themeToggle': '切换主题',
    'accessibility.mobileNav': '移动端面板导航',
    'runtime.pill.label': '运行时:',
    'runtime.pill.switching': '切换中',
    'nav.section': '控制台',
    'nav.overview': '概览',
    'nav.settings': '设置',
    'nav.logs': '日志',
    'nav.management': '管理操作',
    'nav.backup': '备份',
    'nav.mods': 'Mod 管理',
    'nav.runtime': '运行时切换',
    'footer.title': 'Palworld 服务器控制台',
    'panel.overview': '概览',
    'panel.overview.desc': '实时服务器状态与引导操作',
    'chart.fps.title': 'FPS 趋势',
    'chart.fps.current': '当前',
    'chart.fps.avg': '平均',
    'chart.cpu.title': 'CPU 趋势',
    'chart.cpu.label': 'CPU',
    'chart.mem.title': '内存趋势',
    'chart.mem.label': '内存',
    'panel.settings': '设置',
    'panel.settings.desc': '编辑 .env 值。保存后写入文件并重启当前服务。',
    'panel.logs': '日志',
    'panel.logs.desc': '当前服务日志（最近 300 行）',
    'panel.management.title': '管理操作',
    'panel.rcon.desc': '常用操作使用官方 REST API；兼容 RCON 仅在明确启用时显示。',
    'rest.title': 'REST 管理操作',
    'rest.desc': '这些按钮使用结构化 REST 请求，不需要输入自由文本命令。',
    'rest.announce': '服务器公告',
    'rest.announce.placeholder': '输入公告内容',
    'rest.announce.send': '发送公告',
    'rest.playerId': '玩家 ID',
    'rest.playerId.placeholder': '从当前玩家列表复制',
    'rest.playerAction': '玩家操作',
    'rest.kick': '踢出',
    'rest.ban': '封禁',
    'rest.unban': '解封',
    'rest.playerMessage.placeholder': '可选提示消息',
    'rest.player.send': '执行玩家操作',
    'rest.shutdown': '停服等待秒数',
    'rest.shutdown.send': '通过 REST 停服',
    'panel.backup': '备份',
    'panel.backup.desc': '手动与定时备份。存储于 data/backups/',
    'panel.mods': 'Mod 管理',
    'panel.mods.desc': '面向未来 Windows 服务端的受控 Workshop 管理层；当前不安装任何 Mod。',
    'panel.runtime': '运行时切换',
    'panel.runtime.desc': 'Docker 与 Windows 原生服务端互斥切换；切换前自动创建快照。',
    'update.title': '游戏更新',
    'update.state.updating': '正在更新',
    'update.state.completed': '本次启动已完成检查',
    'update.state.disabled': '自动检查已关闭',
    'update.state.waiting': '等待 Docker 启动',
    'update.state.failed': '更新检查失败',
    'update.state.unavailable': '更新状态暂不可读',
    'update.state.unobserved': '本次启动尚无记录',
    'update.state.unsupported': '此运行时不适用',
    'update.auto.on': '启动时自动检查：已启用',
    'update.auto.off': '启动时自动检查：已关闭',
    'update.auto.unknown': '启动时自动检查：状态未读取',
    'update.note.updating': '进度来自 SteamCMD 容器日志；不会触发额外下载或重启。',
    'update.note.completed': 'SteamCMD 在本次容器启动时已完成检查。服务器运行后是否出现新版本，需等下次启动时再次自动确认。',
    'update.note.unobserved': '保留的容器日志中没有本次启动的检查结果，因此不会把它标为“无需更新”。',
    'update.note.disabled': '关闭后，面板不会主动检查上游版本；需在启用后重启时由 SteamCMD 检查。',
    'update.note.unsupported': 'Windows 原生运行时不使用 Docker 镜像的启动更新器。',
    'update.progress.unavailable': '进度暂不可用',
    'runtime.active': '当前运行时',
    'runtime.pid': '进程 PID',
    'runtime.snapshots': '切换快照',
    'runtime.iniCompile': 'INI 编译',
    'runtime.btn.docker': '切换到 Docker',
    'runtime.btn.windows': '切换到 Windows 原生服务端',
    'runtime.btn.current.docker': 'Docker（当前运行中）',
    'runtime.btn.current.windows': 'Windows 原生服务端（当前运行中）',
    'runtime.switch.hint': '当前正在运行 {runtime}。只有另一个蓝色按钮会切换服务；切换前仍会要求确认。',
    'runtime.btn.snapLight': '创建轻量快照',
    'runtime.btn.snapFull': '创建完整快照',
    'runtime.btn.restore': '恢复',
    'runtime.fullSnapshot': '切换前创建完整快照',
    'runtime.junction.title': '存档连接点状态',
    'runtime.snapshots.title': '快照清单',
    'runtime.modal.switch.title': '确认切换运行时？',
    'runtime.modal.restore.title': '确认恢复快照？',
    'mods.guard.title': '兼容性锁已启用',
    'mods.guard.title.ready': 'Mod 管理器已就绪',
    'mods.guard.loading': '正在核对运行时与空清单…',
    'mods.metric.manager': '管理器',
    'mods.metric.runtime': '运行时',
    'mods.metric.configured': '已配置',
    'mods.metric.updates': '待更新',
    'mods.workflow.title': '预留工作流',
    'mods.workflow.body': '从 Steam Workshop 本地源读取 Info.json，校验服务端规则与 SHA-256，经人工批准后同步；不会自动下载未知代码。',
    'mods.btn.check': '检查清单',
    'mods.btn.sync': '同步已批准 Mod',
    'mods.list.title': '清单',
    'mods.state.disabled': '已禁用',
    'mods.state.ready': '可用',
    'mods.state.blocked': '不兼容',
    'mods.reason.disabled': '管理器已在清单中禁用；当前没有 Mod，也不会创建游戏 Mod 目录。',
    'mods.reason.runtime': '当前是 Linux Docker 服务端。Palworld 1.0 官方仅支持 Windows dedicated server 的服务端 Mod。',
    'mods.reason.ready': '运行时兼容且管理器已启用；同步仍要求每个 Mod 通过 Info.json 和 SHA-256 校验。',
    'mods.value.on': '启用',
    'mods.value.off': '禁用',
    'mods.empty': '清单为空。当前没有配置、下载或安装任何 Mod。',
    'mods.status.error': '校验失败',
    'mods.status.missing': '源目录缺失',
    'mods.status.approval': '等待哈希批准',
    'mods.status.installed': '已安装',
    'mods.status.approved': '已批准',
    'mods.status.inactive': '未启用',
    'mods.check.ok': 'Mod 清单检查完成。',
    'mods.sync.ok': '已同步批准的 Mod；重启服务端后生效。',
    'mods.sync.blocked': '同步被安全锁阻止。',
    'mods.modal.sync.title': '同步 Mod？',
    'mods.modal.sync.body': '只会同步清单中已启用且哈希批准的 Workshop 内容；操作后需要重启服务端。',
    'loading.mods': '正在检查 Mod 管理器…',
    'stat.players': '在线玩家',
    'stat.cpu': 'CPU 占用',
    'stat.cpu.ring.windows': 'CPU {cores} 核主机进程占用 {pct}%',
    'stat.cpu.ring.docker': 'CPU {cores} 核配额占用 {pct}%',
    'stat.cpu.limit': '限制：6 核',
    'stat.memory': '内存',
    'stat.status': '服务状态',
    'stat.worldDay': '世界天数',
    'playertimes.title': '玩家在线时长',
    'playertimes.name': '名称',
    'playertimes.total': '已观测时长',
    'playertimes.session': '本次会话',
    'playertimes.count': '会话次数',
    'playertimes.last': '最后在线',
    'playertimes.online': '在线',
    'playertimes.stale': '采集已过期，在线状态未知',
    'playertimes.unknown': '状态未知',
    'playertimes.empty': '暂无玩家记录。玩家进入服务器后会自动累计。',
    'playertimes.updated': '更新于',
    'playertimes.refresh': '刷新',
    'btn.restart': '重启服务',
    'btn.save': '保存世界',
    'btn.backup': '立即备份',
    'btn.stop': '停止',
    'btn.refresh': '刷新',
    'btn.reset': '重置',
    'btn.saveRestart': '保存并重启',
    'btn.send': '发送',
    'log.recent': '最近活动',
    'common.loading': '加载中…',
    'common.noLogs': '暂无日志。',
    'common.noBackups': '暂无备份。点击"立即备份"创建一个。',
    'common.error': '错误',
    'common.networkError': '网络错误',
    'common.confirm': '确认',
    'common.cancel': '取消',
    'logs.autoscroll': '自动滚动',
    'logs.autorefresh': '自动刷新（5秒）',
    'logs.smart': '智能解释',
    'logs.summary.critical': '严重',
    'logs.summary.error': '错误',
    'logs.summary.warning': '警告',
    'logs.summary.recorded': '本次新记录',
    'logs.incidents': '异常记录',
    'logs.incidents.note': '错误自动去重写入 data/diagnostics/incidents.jsonl',
    'logs.archive.title': '每日日志归档',
    'logs.archive.initialNote': '北京时间 00:00–24:00，汇总游戏、面板、隧道与异常记录；永久保留。',
    'logs.archive.refresh': '立即归档今天',
    'logs.explanation': '译解',
    'logs.suggestion': '建议',
    'settings.search.placeholder': '搜索设置…',
    'settings.catalogLoading': '正在载入镜像能力清单…',
    'settings.groupFilter': '设置分组',
    'settings.notice': '保存只写入已修改字段；密码和 Webhook 为只写项，不会从后端回显。应用修改会重启当前服务，在线玩家会断开。',
    'settings.undo': '撤销',
    'settings.noMatch': '没有匹配的设置项',
    'settings.collapseAll': '全部折叠',
    'settings.expandAll': '全部展开',
    'settings.collapseHint': '点击折叠/展开',
    'tunnel.proofTitle': '隧道证据链',
    'tunnel.timelineTitle': '异常时间轴',
    'tunnel.timelineEmpty': '暂无隧道相关异常记录',
    'tunnel.step.localUdp': '本地 UDP',
    'tunnel.step.process': 'frpc 进程',
    'tunnel.step.control': '控制连接',
    'tunnel.step.proxy': '隧道就绪',
    'tunnel.step.traffic': '外部流量',
    'settings.saved': '已保存 {n} 项修改。',
    'settings.restarted': '当前服务已重启。',
    'settings.noChanges': '没有修改需要保存。',
    'settings.saveFailed': '保存失败',
    'settings.restartFailed': '重启失败',
    'rcon.ready': 'RCON 控制台就绪。输入命令或从右侧选择。',
    'rcon.input.placeholder': '例如 showplayers',
    'rcon.quickcmds': '快捷命令',
    'rcon.empty': '(无输出)',
    'rcon.error': 'RCON 错误',
    'rcon.doc.before': '单击只会填入命令，不会立即执行。命令依据 ',
    'rcon.doc.link': 'Palworld 官方命令表',
    'rcon.doc.after': '。',
    'rcon.playerPicker.action': '填入指令',
    'rcon.playerPicker.steamId': 'Steam ID',
    'rcon.playerPicker.playerUid': 'Player UID',
    'rcon.playerPicker.use': '填入 {kind}',
    'rcon.playerPicker.inserted': '{name} 的 {kind} 已填入指令框，尚未执行。',
    'rcon.playerPicker.unavailable': '该玩家标识已不在当前在线列表中。',
    'rcon.guide.title': '按目标操作',
    'rcon.guide.desc': '不需要记住指令。先选择任务，再检查输入框，最后由你决定是否发送。',
    'rcon.guide.players': '查看在线玩家',
    'rcon.guide.players.desc': '回到概览读取实时玩家表；管理玩家时可点选 ID。',
    'rcon.guide.info': '读取服务器信息',
    'rcon.guide.info.desc': '填入只读 info 指令。',
    'rcon.guide.broadcast': '准备服务器公告',
    'rcon.guide.broadcast.desc': '把公告文字生成指令，不会立即发送。',
    'rcon.broadcast.label': '公告内容',
    'rcon.broadcast.placeholder': '例如：10 分钟后维护，请安全下线',
    'rcon.broadcast.prepare': '填入公告指令',
    'rcon.broadcast.empty': '请先输入公告内容。',
    'rcon.broadcast.ready': '公告指令已填入，尚未发送。',
    'rcon.guide.playerHelp': '玩家管理：先在概览选择“填入指令”，再回到此处确认并发送。封禁、踢出和停服均会二次确认。',
    'modal.rcon.player.title': '确认执行玩家管理？',
    'modal.rcon.player.body': '这会立即向当前服务发送玩家管理指令。请先确认选择的玩家和指令类型。',
    'modal.rcon.runtime.title': '确认执行高风险指令？',
    'modal.rcon.runtime.body': '这会立即向当前服务发送停服或退出指令。请确认玩家已收到通知并且已完成保存和备份。',
    'guide.title': '从这里开始',
    'guide.desc': '不了解指令也可以完成日常管理。选择目标后，面板会说明接下来会发生什么。',
    'guide.save.title': '保存世界',
    'guide.save.desc': '立即请求当前服务保存；不会停止服务。',
    'guide.backup.title': '创建备份',
    'guide.backup.desc': '先保存，再由当前运行时创建本地归档。',
    'guide.players.title': '查看或管理玩家',
    'guide.players.desc': '查看实时玩家表；需要管理时点选 ID 填入指令。',
    'guide.tunnel.title': '检查好友能否加入',
    'guide.tunnel.desc': '重新读取隧道证据；“已启动”不等于好友已能进入。',
    'guide.logs.title': '排查问题',
    'guide.logs.desc': '打开带解释和建议的日志，而不是直接阅读原始输出。',
    'guide.order': '建议顺序：保存世界 → 创建备份 → 再进行停服、重启或切换。',
    'backup.trigger': '触发备份',
    'backup.trigger.desc': '当前运行时会先保存世界，再创建本地备份归档。耗时取决于世界大小。',
    'backup.existing': '现有备份',
    'backup.created': '备份已创建。',
    'backup.error': '备份错误',
    'backup.download': '下载',
    'backup.downloading': '准备中…',
    'modal.restart.title': '重启当前服务？',
    'modal.restart.body': '当前服务会短暂不可用，在线玩家会断开。继续前请确认已保存并已创建备份。',
    'modal.stop.title': '停止当前服务？',
    'modal.stop.body': '会请求当前服务优雅退出，并最多等待 120 秒。在线玩家会断开。',
    'modal.save.title': '保存并重启？',
    'modal.save.body': '将写入 {n} 项修改到 .env，然后重启当前服务。玩家会断开连接。',
    'modal.stopSignal': '已发送停止信号。',
    'toast.saved': '已保存',
    'toast.reset': '已重置',
    'toast.noChanges': '无修改',
    'toast.ok': '成功',
    'toast.worldSaved': '世界已保存。',
    'toast.containerRestarted': '服务已重启。',
    'toast.stopSignal': '服务已停止。',
    'toast.backupCreated': '备份已创建。',
    'toast.reloading': '重启中…',
    'toast.loading': '处理中…',
    'loading.restarting': '正在重启服务…',
    'loading.saving': '正在保存世界…',
    'loading.backup': '正在备份…',
    'loading.stopping': '正在停止…',
    'loading.savingEnv': '保存 .env 并重启中…',
    // RCON command descriptions
    'rconcmd.showplayers': '列出在线玩家',
    'rconcmd.info': '服务器信息',
    'rconcmd.save': '保存世界',
    'rconcmd.doexit': '关闭服务器（慎用）',
    'rconcmd.broadcast': '全服广播',
    'rconcmd.kickplayer': '踢出玩家',
    'rconcmd.banplayer': '封禁玩家',
    'rconcmd.unbanplayer': '解封玩家',
    'rconcmd.teleporttoplayer': '把管理员传送到指定玩家',
    'rconcmd.teleporttome': '把指定玩家传送到管理员',
    'rconcmd.togglespectate': '切换观战模式',
    'rconcmd.shutdown': '60秒后关服',
    // Settings field labels
    'field.serverName': '服务器名称',
    'field.serverDesc': '服务器描述',
    'field.maxPlayers': '最大玩家数',
    'field.serverPassword': '服务器密码',
    'field.expRate': '经验倍率',
    'field.palCaptureRate': '捕捉率',
    'field.palSpawnNumRate': '帕鲁生成数量',
    'field.workSpeedRate': '工作速度',
    'field.collectionDropRate': '采集掉落倍率',
    'field.enemyDropItemRate': '敌人掉落倍率',
    'field.dayTimeSpeedRate': '白天速度',
    'field.nightTimeSpeedRate': '夜晚速度',
    'field.palEggDefaultHatchingTime': '孵蛋时间倍率',
    'field.autoSaveSpan': '自动保存间隔（秒）',
    'field.supplyDropSpan': '空投间隔（分钟）',
    'field.playerDamageRateAttack': '玩家攻击伤害',
    'field.playerDamageRateDefense': '玩家受伤倍率',
    'field.palDamageRateAttack': '帕鲁攻击伤害',
    'field.palDamageRateDefense': '帕鲁受伤倍率',
    'field.deathPenalty': '死亡惩罚',
    'field.bEnablePlayerToPlayerDamage': '玩家间伤害',
    'field.bEnableFriendlyFire': '友军伤害',
    'field.bIsPvp': 'PvP 模式',
    'field.bEnableInvaderEnemy': '入侵者敌人',
    'field.playerStomachDecreaceRate': '玩家饥饿速率',
    'field.playerStaminaDecreaceRate': '玩家耐力消耗',
    'field.playerAutoHpRegeneRate': '玩家自动回血',
    'field.playerAutoHpRegeneRateInSleep': '玩家睡眠回血',
    'field.palStomachDecreaceRate': '帕鲁饥饿速率',
    'field.palStaminaDecreaceRate': '帕鲁耐力消耗',
    'field.palAutoHpRegeneRate': '帕鲁自动回血',
    'field.palAutoHpRegeneRateInSleep': '帕鲁睡眠回血',
    'field.buildObjectHpRate': '建筑血量',
    'field.buildObjectDamageRate': '建筑受伤倍率',
    'field.buildObjectDeteriorationDamageRate': '建筑腐坏速率',
    'field.baseCampMaxNum': '据点上限',
    'field.baseCampWorkerMaxNum': '据点帕鲁上限',
    'field.dropItemMaxNum': '掉落物上限',
    'field.guildPlayerMaxNum': '公会玩家上限',
    'field.bEnableFastTravel': '启用快速旅行',
    'field.bShowPlayerList': '显示玩家列表',
    // Setting groups
    'group.基础': '基础',
    'group.游戏速率': '游戏速率',
    'group.时间': '时间',
    'group.战斗': '战斗',
    'group.生存': '生存',
    'group.建筑': '建筑',
    'group.其他': '其他',
    // Hints
    'hint.serverPassword': '留空 = 无密码',
    'hint.dayTimeSpeedRate': '越小越快',
    'hint.nightTimeSpeedRate': '越小越快',
    'hint.palEggDefaultHatchingTime': '越小越快',
  },
  en: {
    'status.connecting': 'CONNECTING…',
    'status.online': 'ONLINE',
    'status.starting': 'STARTING',
    'status.stopped': 'STOPPED',
    'status.absent': 'ABSENT',
    'status.restarting': 'RESTARTING',
    'status.unknown': 'UNKNOWN',
    'status.offline': 'OFFLINE',
    'meta.uptime': 'UPTIME',
    'meta.port': 'PORT',
    'accessibility.runtimePill': 'Current runtime',
    'accessibility.languageToggle': 'Switch language',
    'accessibility.themeToggle': 'Toggle theme',
    'accessibility.mobileNav': 'Mobile panel navigation',
    'runtime.pill.label': 'Runtime:',
    'runtime.pill.switching': 'Switching',
    'nav.section': 'Console',
    'nav.overview': 'Overview',
    'nav.settings': 'Settings',
    'nav.logs': 'Logs',
    'nav.management': 'Management',
    'nav.backup': 'Backup',
    'nav.mods': 'Mod Manager',
    'nav.runtime': 'Runtime Switch',
    'footer.title': 'Palworld Server Console',
    'panel.overview': 'OVERVIEW',
    'panel.overview.desc': 'Live server status and guided actions',
    'chart.fps.title': 'FPS Trend',
    'chart.fps.current': 'Current',
    'chart.fps.avg': 'Average',
    'chart.cpu.title': 'CPU Trend',
    'chart.cpu.label': 'CPU',
    'chart.mem.title': 'Memory Trend',
    'chart.mem.label': 'Memory',
    'panel.settings': 'SETTINGS',
    'panel.settings.desc': 'Edit .env values. Saving writes the file and restarts the active service.',
    'panel.logs': 'LOGS',
    'panel.logs.desc': 'Current service logs (last 300 lines)',
    'panel.management.title': 'MANAGEMENT',
    'panel.rcon.desc': 'Common operations use the official REST API. Legacy RCON appears only when explicitly enabled.',
    'rest.title': 'REST management operations',
    'rest.desc': 'These controls send structured REST requests instead of free-form commands.',
    'rest.announce': 'Server announcement',
    'rest.announce.placeholder': 'Enter an announcement',
    'rest.announce.send': 'Send announcement',
    'rest.playerId': 'Player ID',
    'rest.playerId.placeholder': 'Copy from the current player table',
    'rest.playerAction': 'Player action',
    'rest.kick': 'Kick',
    'rest.ban': 'Ban',
    'rest.unban': 'Unban',
    'rest.playerMessage.placeholder': 'Optional message',
    'rest.player.send': 'Run player action',
    'rest.shutdown': 'Shutdown wait seconds',
    'rest.shutdown.send': 'Shutdown through REST',
    'panel.backup': 'BACKUP',
    'panel.backup.desc': 'Manual & scheduled backups. Stored in data/backups/',
    'panel.mods': 'MOD MANAGER',
    'panel.mods.desc': 'A controlled Workshop layer reserved for a future Windows server. No Mods are installed.',
    'panel.runtime': 'RUNTIME SWITCH',
    'panel.runtime.desc': 'Switch exclusively between Docker and the Windows native server. A snapshot is created before switching.',
    'update.title': 'GAME UPDATE',
    'update.state.updating': 'Updating',
    'update.state.completed': 'Checked at this startup',
    'update.state.disabled': 'Automatic check disabled',
    'update.state.waiting': 'Waiting for Docker',
    'update.state.failed': 'Update check failed',
    'update.state.unavailable': 'Update status unavailable',
    'update.state.unobserved': 'No startup record retained',
    'update.state.unsupported': 'Not applicable to this runtime',
    'update.auto.on': 'Automatic startup check: enabled',
    'update.auto.off': 'Automatic startup check: disabled',
    'update.auto.unknown': 'Automatic startup check: status not loaded',
    'update.note.updating': 'Progress is read from SteamCMD container logs; it does not trigger another download or restart.',
    'update.note.completed': 'SteamCMD completed its check during this container startup. A new upstream release after startup is confirmed only by the next automatic startup check.',
    'update.note.unobserved': 'The retained container logs have no result for this startup, so the panel will not label it up to date.',
    'update.note.disabled': 'With this disabled, the panel does not query upstream versions; SteamCMD checks again only after it is enabled and the container starts.',
    'update.note.unsupported': 'The Windows native runtime does not use the Docker image startup updater.',
    'update.progress.unavailable': 'Progress unavailable',
    'runtime.active': 'Active Runtime',
    'runtime.pid': 'Process PID',
    'runtime.snapshots': 'Switch Snapshots',
    'runtime.iniCompile': 'INI Compilation',
    'runtime.btn.docker': 'Switch to Docker',
    'runtime.btn.windows': 'Switch to Windows Native',
    'runtime.btn.current.docker': 'Docker (currently running)',
    'runtime.btn.current.windows': 'Windows Native (currently running)',
    'runtime.switch.hint': '{runtime} is currently running. Only the other blue button switches the server, and it will still ask for confirmation.',
    'runtime.btn.snapLight': 'Create Light Snapshot',
    'runtime.btn.snapFull': 'Create Full Snapshot',
    'runtime.btn.restore': 'Restore',
    'runtime.fullSnapshot': 'Create a full snapshot before switching',
    'runtime.junction.title': 'Save Junction Status',
    'runtime.snapshots.title': 'Snapshot List',
    'runtime.modal.switch.title': 'Switch Runtime?',
    'runtime.modal.restore.title': 'Restore Snapshot?',
    'mods.guard.title': 'COMPATIBILITY LOCK ACTIVE',
    'mods.guard.title.ready': 'Mod Manager Ready',
    'mods.guard.loading': 'Checking runtime and empty manifest…',
    'mods.metric.manager': 'Manager',
    'mods.metric.runtime': 'Runtime',
    'mods.metric.configured': 'Configured',
    'mods.metric.updates': 'Updates',
    'mods.workflow.title': 'Reserved Workflow',
    'mods.workflow.body': 'Reads Info.json from a local Steam Workshop source, validates server rules and SHA-256, then syncs only after manual approval. Unknown code is never downloaded automatically.',
    'mods.btn.check': 'Check Manifest',
    'mods.btn.sync': 'Sync Approved Mods',
    'mods.list.title': 'Manifest',
    'mods.state.disabled': 'DISABLED',
    'mods.state.ready': 'READY',
    'mods.state.blocked': 'UNSUPPORTED',
    'mods.reason.disabled': 'The manager is disabled in the manifest. No Mods are configured and no game Mod directories will be created.',
    'mods.reason.runtime': 'This server uses Linux Docker. Official Palworld 1.0 server Mods currently require the Windows dedicated server.',
    'mods.reason.ready': 'The runtime is compatible and the manager is enabled. Every Mod must still pass Info.json and SHA-256 validation.',
    'mods.value.on': 'ON',
    'mods.value.off': 'OFF',
    'mods.empty': 'The manifest is empty. No Mods are configured, downloaded, or installed.',
    'mods.status.error': 'VALIDATION ERROR',
    'mods.status.missing': 'SOURCE MISSING',
    'mods.status.approval': 'HASH APPROVAL NEEDED',
    'mods.status.installed': 'INSTALLED',
    'mods.status.approved': 'APPROVED',
    'mods.status.inactive': 'INACTIVE',
    'mods.check.ok': 'Mod manifest check completed.',
    'mods.sync.ok': 'Approved Mods synced. Restart the server to apply them.',
    'mods.sync.blocked': 'The safety lock blocked synchronization.',
    'mods.modal.sync.title': 'Sync Mods?',
    'mods.modal.sync.body': 'Only enabled, hash-approved Workshop content will be synchronized. The server must be restarted afterward.',
    'loading.mods': 'Checking Mod manager…',
    'stat.players': 'Players Online',
    'stat.cpu': 'CPU Usage',
    'stat.cpu.ring.windows': 'CPU process usage {pct}% on a {cores}-core host',
    'stat.cpu.ring.docker': 'CPU allocation usage {pct}% of {cores} cores',
    'stat.cpu.limit': 'limit: 6 cores',
    'stat.memory': 'Memory',
    'stat.status': 'Service Status',
    'stat.worldDay': 'World Day',
    'playertimes.title': 'Player Online Time',
    'playertimes.name': 'Name',
    'playertimes.total': 'Observed Time',
    'playertimes.session': 'Current Session',
    'playertimes.count': 'Sessions',
    'playertimes.last': 'Last Seen',
    'playertimes.online': 'online',
    'playertimes.stale': 'collection is stale; online state is unknown',
    'playertimes.unknown': 'unknown',
    'playertimes.empty': 'No player records yet. Time accumulates once players join.',
    'playertimes.updated': 'Updated',
    'playertimes.refresh': 'Refresh',
    'btn.restart': 'Restart Service',
    'btn.save': 'Save World',
    'btn.backup': 'Backup Now',
    'btn.stop': 'Stop',
    'btn.refresh': 'Refresh',
    'btn.reset': 'Reset',
    'btn.saveRestart': 'Save & Restart',
    'btn.send': 'Send',
    'log.recent': 'Recent Activity',
    'common.loading': 'Loading…',
    'common.noLogs': 'No logs.',
    'common.noBackups': 'No backups yet. Click "Backup Now" to create one.',
    'common.error': 'Error',
    'common.networkError': 'Network',
    'common.confirm': 'Confirm',
    'common.cancel': 'Cancel',
    'logs.autoscroll': 'Auto-scroll',
    'logs.autorefresh': 'Auto-refresh (5s)',
    'logs.smart': 'Smart explanations',
    'logs.summary.critical': 'Critical',
    'logs.summary.error': 'Errors',
    'logs.summary.warning': 'Warnings',
    'logs.summary.recorded': 'New this session',
    'logs.incidents': 'Incidents',
    'logs.incidents.note': 'Errors are deduplicated in data/diagnostics/incidents.jsonl',
    'logs.archive.title': 'Daily log archives',
    'logs.archive.initialNote': '00:00–24:00 Asia/Shanghai; combines game, panel, tunnel, and incident records; retained indefinitely.',
    'logs.archive.refresh': 'Archive today',
    'logs.explanation': 'Explanation',
    'logs.suggestion': 'Suggested action',
    'settings.search.placeholder': 'Search settings…',
    'settings.catalogLoading': 'Loading image capability catalog…',
    'settings.groupFilter': 'Setting group',
    'settings.notice': 'Only modified fields are written. Passwords and webhooks are write-only and never returned. Applying changes restarts the active service and disconnects players.',
    'settings.undo': 'Undo',
    'settings.noMatch': 'No settings match',
    'settings.collapseAll': 'Collapse all',
    'settings.expandAll': 'Expand all',
    'settings.collapseHint': 'Click to collapse/expand',
    'tunnel.proofTitle': 'Tunnel Evidence Chain',
    'tunnel.timelineTitle': 'Anomaly Timeline',
    'tunnel.timelineEmpty': 'No tunnel anomalies recorded',
    'tunnel.step.localUdp': 'Local UDP',
    'tunnel.step.process': 'frpc process',
    'tunnel.step.control': 'Control conn',
    'tunnel.step.proxy': 'Proxy ready',
    'tunnel.step.traffic': 'Ext traffic',
    'settings.saved': 'Saved {n} change(s).',
    'settings.restarted': 'Active service restarted.',
    'settings.noChanges': 'No changes to save.',
    'settings.saveFailed': 'Save failed',
    'settings.restartFailed': 'Restart failed',
    'rcon.ready': 'RCON console ready. Type a command or pick from the right.',
    'rcon.input.placeholder': 'e.g. showplayers',
    'rcon.quickcmds': 'Quick Commands',
    'rcon.empty': '(no output)',
    'rcon.error': 'RCON Error',
    'rcon.doc.before': 'Clicking a command only fills the input; it does not execute it. Commands follow the ',
    'rcon.doc.link': 'official Palworld command reference',
    'rcon.doc.after': '.',
    'rcon.playerPicker.action': 'Insert into command',
    'rcon.playerPicker.steamId': 'Steam ID',
    'rcon.playerPicker.playerUid': 'Player UID',
    'rcon.playerPicker.use': 'Insert {kind}',
    'rcon.playerPicker.inserted': '{kind} for {name} was inserted into the command input; it was not executed.',
    'rcon.playerPicker.unavailable': 'This player identifier is no longer in the current online-player list.',
    'rcon.guide.title': 'Choose a goal',
    'rcon.guide.desc': 'You do not need to memorize commands. Choose a task, review the input, then decide whether to send it.',
    'rcon.guide.players': 'View online players',
    'rcon.guide.players.desc': 'Return to the Overview for the live player table and selectable IDs.',
    'rcon.guide.info': 'Read server information',
    'rcon.guide.info.desc': 'Fills the read-only info command.',
    'rcon.guide.broadcast': 'Prepare an announcement',
    'rcon.guide.broadcast.desc': 'Generates an announcement command without sending it.',
    'rcon.broadcast.label': 'Announcement text',
    'rcon.broadcast.placeholder': 'e.g. Maintenance begins in 10 minutes; please log out safely',
    'rcon.broadcast.prepare': 'Fill announcement command',
    'rcon.broadcast.empty': 'Enter the announcement text first.',
    'rcon.broadcast.ready': 'The announcement command was filled in; it was not sent.',
    'rcon.guide.playerHelp': 'Player management: select “Insert into command” on Overview, then review and send it here. Ban, kick, and server-stop commands require a second confirmation.',
    'modal.rcon.player.title': 'Run player-management command?',
    'modal.rcon.player.body': 'This immediately sends a player-management command to the active service. Confirm the selected player and action first.',
    'modal.rcon.runtime.title': 'Run high-risk command?',
    'modal.rcon.runtime.body': 'This immediately sends a shutdown or exit command to the active service. Confirm players were notified and a save and backup are complete.',
    'guide.title': 'Start here',
    'guide.desc': 'Complete everyday administration without knowing commands. Each goal explains what happens next.',
    'guide.save.title': 'Save the world',
    'guide.save.desc': 'Ask the active service to save now; it does not stop the service.',
    'guide.backup.title': 'Create a backup',
    'guide.backup.desc': 'Save first, then create a local archive through the active runtime.',
    'guide.players.title': 'View or manage players',
    'guide.players.desc': 'Read the live player table; select an ID to fill a management command.',
    'guide.tunnel.title': 'Check whether friends can join',
    'guide.tunnel.desc': 'Refresh tunnel evidence; “started” does not mean a friend can join.',
    'guide.logs.title': 'Investigate a problem',
    'guide.logs.desc': 'Open explained logs with suggested actions instead of raw output alone.',
    'guide.order': 'Suggested order: save the world → create a backup → then stop, restart, or switch.',
    'backup.trigger': 'Trigger Backup',
    'backup.trigger.desc': 'The active runtime saves the world first, then creates a local backup archive. Duration depends on world size.',
    'backup.existing': 'Existing Backups',
    'backup.created': 'Backup created.',
    'backup.error': 'Backup Error',
    'backup.download': 'Download',
    'backup.downloading': 'Preparing…',
    'modal.restart.title': 'Restart the active service?',
    'modal.restart.body': 'The active service will be briefly unavailable and online players will disconnect. Confirm a save and backup are complete first.',
    'modal.stop.title': 'Stop the active service?',
    'modal.stop.body': 'The active service is asked to exit gracefully and is given up to 120 seconds. Online players will disconnect.',
    'modal.save.title': 'Save & Restart?',
    'modal.save.body': 'Writing {n} change(s) to .env, then restarting the active service. Players will be disconnected.',
    'modal.stopSignal': 'Stop signal sent.',
    'toast.saved': 'SAVED',
    'toast.reset': 'RESET',
    'toast.noChanges': 'NO CHANGES',
    'toast.ok': 'OK',
    'toast.worldSaved': 'World saved.',
    'toast.containerRestarted': 'Service restarted.',
    'toast.stopSignal': 'Service stopped.',
    'toast.backupCreated': 'Backup created.',
    'toast.reloading': 'Restarting…',
    'toast.loading': 'Working…',
    'loading.restarting': 'Restarting service…',
    'loading.saving': 'Saving world…',
    'loading.backup': 'Running backup…',
    'loading.stopping': 'Stopping…',
    'loading.savingEnv': 'Saving .env & restarting…',
    'rconcmd.showplayers': 'List online players',
    'rconcmd.info': 'Server info',
    'rconcmd.save': 'Save world',
    'rconcmd.doexit': 'Shutdown server (use with caution)',
    'rconcmd.broadcast': 'Broadcast to all',
    'rconcmd.kickplayer': 'Kick player',
    'rconcmd.banplayer': 'Ban player',
    'rconcmd.unbanplayer': 'Unban player',
    'rconcmd.teleporttoplayer': 'Teleport admin to player',
    'rconcmd.teleporttome': 'Teleport player to admin',
    'rconcmd.togglespectate': 'Toggle spectator mode',
    'rconcmd.shutdown': 'Shutdown in 60s',
    'field.serverName': 'Server Name',
    'field.serverDesc': 'Server Description',
    'field.maxPlayers': 'Max Players',
    'field.serverPassword': 'Server Password',
    'field.expRate': 'XP Rate',
    'field.palCaptureRate': 'Capture Rate',
    'field.palSpawnNumRate': 'Pal Spawn Count',
    'field.workSpeedRate': 'Work Speed',
    'field.collectionDropRate': 'Collection Drop Rate',
    'field.enemyDropItemRate': 'Enemy Drop Rate',
    'field.dayTimeSpeedRate': 'Day Time Speed',
    'field.nightTimeSpeedRate': 'Night Time Speed',
    'field.palEggDefaultHatchingTime': 'Egg Hatch Time',
    'field.autoSaveSpan': 'Auto Save Interval (s)',
    'field.supplyDropSpan': 'Supply Drop Interval (min)',
    'field.playerDamageRateAttack': 'Player Attack Damage',
    'field.playerDamageRateDefense': 'Player Damage Taken',
    'field.palDamageRateAttack': 'Pal Attack Damage',
    'field.palDamageRateDefense': 'Pal Damage Taken',
    'field.deathPenalty': 'Death Penalty',
    'field.bEnablePlayerToPlayerDamage': 'Player vs Player Damage',
    'field.bEnableFriendlyFire': 'Friendly Fire',
    'field.bIsPvp': 'PvP Mode',
    'field.bEnableInvaderEnemy': 'Invader Enemy',
    'field.playerStomachDecreaceRate': 'Player Hunger Rate',
    'field.playerStaminaDecreaceRate': 'Player Stamina Use',
    'field.playerAutoHpRegeneRate': 'Player HP Regen',
    'field.playerAutoHpRegeneRateInSleep': 'Player Sleep HP Regen',
    'field.palStomachDecreaceRate': 'Pal Hunger Rate',
    'field.palStaminaDecreaceRate': 'Pal Stamina Use',
    'field.palAutoHpRegeneRate': 'Pal HP Regen',
    'field.palAutoHpRegeneRateInSleep': 'Pal Sleep HP Regen',
    'field.buildObjectHpRate': 'Building HP',
    'field.buildObjectDamageRate': 'Building Damage Taken',
    'field.buildObjectDeteriorationDamageRate': 'Building Deterioration',
    'field.baseCampMaxNum': 'Base Camp Max',
    'field.baseCampWorkerMaxNum': 'Base Camp Pal Max',
    'field.dropItemMaxNum': 'Drop Item Max',
    'field.guildPlayerMaxNum': 'Guild Player Max',
    'field.bEnableFastTravel': 'Enable Fast Travel',
    'field.bShowPlayerList': 'Show Player List',
    'group.基础': 'Basic',
    'group.游戏速率': 'Rates',
    'group.时间': 'Time',
    'group.战斗': 'Combat',
    'group.生存': 'Survival',
    'group.建筑': 'Building',
    'group.其他': 'Other',
    'hint.serverPassword': 'empty = no password',
    'hint.dayTimeSpeedRate': 'lower = faster',
    'hint.nightTimeSpeedRate': 'lower = faster',
    'hint.palEggDefaultHatchingTime': 'lower = faster',
  }
};

function t(key, vars) {
  let s = I18N[currentLang][key] || I18N.zh[key] || key;
  if (vars) {
    Object.keys(vars).forEach(k => { s = s.replace('{' + k + '}', vars[k]); });
  }
  return s;
}

// Player times cache (declared early so applyI18n can safely reference it).
let playerTimesCache = null;

function applyI18n() {
  document.querySelectorAll('[data-i18n]').forEach(el => {
    el.textContent = t(el.dataset.i18n);
  });
  document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
    el.placeholder = t(el.dataset.i18nPlaceholder);
  });
  document.querySelectorAll('[data-i18n-title]').forEach(el => {
    el.title = t(el.dataset.i18nTitle);
  });
  document.querySelectorAll('[data-i18n-aria-label]').forEach(el => {
    el.setAttribute('aria-label', t(el.dataset.i18nAriaLabel));
  });
  document.documentElement.setAttribute('lang', currentLang === 'zh' ? 'zh-CN' : 'en');
  $('langLabel').textContent = currentLang === 'zh' ? '中' : 'EN';
  // Re-render dynamic panels to refresh their text
  if (typeof renderRconCmds === 'function') renderRconCmds();
  if (typeof populateGroupFilter === 'function' && FIELDS.length) populateGroupFilter();
  if (typeof renderSettings === 'function') renderSettings();
  if (typeof renderDashboard === 'function' && dashboardState) renderDashboard(dashboardState);
  if (typeof loadBackups === 'function' && document.querySelector('#panel-backup.active')) loadBackups();
  if (typeof renderMods === 'function' && modState) renderMods();
  if (typeof renderPlayerTimes === 'function' && playerTimesCache) renderPlayerTimes(playerTimesCache);
}

function initLang() {
  currentLang = localStorage.getItem('pw-lang') || 'zh';
  applyI18n();
}

function toggleLang() {
  currentLang = currentLang === 'zh' ? 'en' : 'zh';
  localStorage.setItem('pw-lang', currentLang);
  applyI18n();
  // Runtime target labels are stateful, so restore the current-runtime state
  // immediately instead of waiting for a later panel refresh.
  if (typeof updateRuntimeSwitchControls === 'function') updateRuntimeSwitchControls(runtimeState);
  // Also re-render RCON commands (labels) and re-fetch state (status label)
  refreshState();
}

// ===== Helpers =====
const $ = id => document.getElementById(id);

// ===== Theme =====
function initTheme() {
  const saved = localStorage.getItem('pw-theme') || 'dark';
  document.documentElement.setAttribute('data-theme', saved);
}
function toggleTheme() {
  const current = document.documentElement.getAttribute('data-theme') || 'dark';
  const next = current === 'dark' ? 'light' : 'dark';
  document.documentElement.setAttribute('data-theme', next);
  localStorage.setItem('pw-theme', next);
  // Redraw charts immediately so colors match the new theme.
  resetAllChartContexts();
}
initTheme();
initLang();

async function api(path, opts = {}) {
  const options = {cache: 'no-store', ...opts};
  options.headers = {
    'Accept': 'application/json',
    ...(opts.headers || {})
  };
  const r = await fetch(path, options);
  let payload = null;
  try { payload = await r.json(); } catch (_) {}
  if (!r.ok) throw new Error(payload?.error || `HTTP ${r.status}`);
  return payload;
}

function toast(msg, type = 'success', title = null) {
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.innerHTML = `<div class="title">${escapeHtml(title || type.toUpperCase())}</div><div class="msg">${escapeHtml(msg)}</div>`;
  $('toastContainer').appendChild(el);
  setTimeout(() => { el.style.opacity = '0'; el.style.transition = 'opacity 0.3s'; setTimeout(() => el.remove(), 300); }, 3500);
}

function showLoading(text = 'Working…') {
  $('loadingText').textContent = text;
  $('loadingOverlay').classList.add('show');
}
function hideLoading() { $('loadingOverlay').classList.remove('show'); }

function showModal(title, body) {
  return new Promise((resolve) => {
    $('modalTitle').textContent = title;
    $('modalBody').textContent = body;
    $('modalBackdrop').classList.add('show');
    const cleanup = () => {
      $('modalBackdrop').classList.remove('show');
      $('modalConfirm').onclick = null;
      $('modalCancel').onclick = null;
    };
    $('modalConfirm').onclick = () => { cleanup(); resolve(true); };
    $('modalCancel').onclick = () => { cleanup(); resolve(false); };
  });
}

// ===== Navigation =====
// Event delegation so the handler also covers the mobile tab bar items
// cloned into #mobileTabbar at init time.
function activatePanel(panel) {
  if (!panel) return;
  document.querySelectorAll('.nav-item').forEach(n => n.classList.toggle('active', n.dataset.panel === panel));
  document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
  const target = $(`panel-${panel}`);
  if (target) target.classList.add('active');
  if (panel === 'logs') loadLogs();
  if (panel === 'backup') loadBackups();
  if (panel === 'mods') loadMods();
  if (panel === 'settings') loadEnv();
  if (panel === 'runtime') loadRuntime();
}
document.addEventListener('click', (e) => {
  const item = e.target.closest('.nav-item');
  if (!item || !item.dataset.panel) return;
  activatePanel(item.dataset.panel);
});

// Populate the mobile bottom tab bar by cloning the sidebar nav items,
// so there is a single source of truth for labels and icons.
(function buildMobileTabbar() {
  const bar = $('mobileTabbar');
  if (!bar) return;
  const source = document.querySelectorAll('.sidebar .nav-item');
  source.forEach(node => {
    const clone = node.cloneNode(true);
    // Strip the nav-section text and any non-icon extras; keep icon + first label span.
    bar.appendChild(clone);
  });
})();

// ===== State polling =====
const STATUS_KEY_MAP = { running: 'status.online', starting: 'status.starting', stopped: 'status.stopped', absent: 'status.absent', restarting: 'status.restarting', unknown: 'status.unknown' };
async function refreshState() {
  try {
    dashboardState = await api('/api/dashboard');
    renderDashboard(dashboardState);
    if (dashboardState && dashboardState.runtime) {
      updateRuntimePill(dashboardState.runtime);
    }
    refreshUpdateStatusFallback().catch(() => {});
    // Non-blocking: refresh tunnel anomaly timeline alongside dashboard
    loadTunnelIncidents().then(renderTunnelTimeline).catch(() => {});
    // Non-blocking: refresh player online-time records
    refreshPlayerTimes().catch(() => {});
  } catch (e) {
    $('statusText').textContent = t('status.offline');
    $('statusDot').className = 'status-dot stopped';
    $('dashboardFreshness').textContent = (currentLang === 'zh' ? '状态读取失败：' : 'Status failed: ') + e.message;
  }
}

function updateRuntimePill(runtimeInfo) {
  if (!runtimeInfo || !runtimeInfo.ok) return;
  const r = runtimeInfo.runtime || {};
  const valueEl = $('runtimePillValue');
  const switchingEl = $('runtimePillSwitching');
  const active = String(r.active || 'none');
  valueEl.textContent = active.toUpperCase();
  valueEl.className = 'runtime-pill-value ' + active;
  if (r.switching) {
    switchingEl.hidden = false;
  } else {
    switchingEl.hidden = true;
  }
}

function numberOr(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function formatDuration(seconds) {
  let total = Math.max(0, Math.floor(numberOr(seconds)));
  const days = Math.floor(total / 86400); total %= 86400;
  const hours = Math.floor(total / 3600); total %= 3600;
  const minutes = Math.floor(total / 60); total %= 60;
  if (days) return `${days}d ${hours}h`;
  if (hours) return `${hours}h ${minutes}m`;
  if (minutes) return `${minutes}m ${total}s`;
  return `${total}s`;
}

function maskIdentifier(value) {
  const s = String(value ?? '');
  if (!s) return '—';
  if (/^\d{1,3}(\.\d{1,3}){3}(:\d+)?$/.test(s)) {
    return s.replace(/(\d{1,3})$/, '•••');
  }
  if (s.length <= 8) return '••••';
  return `${s.slice(0, 4)}••••${s.slice(-4)}`;
}

function serviceRow(key, value, state = '') {
  const chip = state
    ? `<span class="health-chip ${escapeHtml(state)}">${escapeHtml(value)}</span>`
    : escapeHtml(value);
  return `<div class="service-row"><span class="key">${escapeHtml(key)}</span><span class="value">${chip}</span></div>`;
}

function tunnelStateLabel(tunnel) {
  const labels = currentLang === 'zh' ? {
    absent:'未检测到客户端', starting:'正在建立连接', 'local-not-ready':'本地 UDP 未监听',
    'network-unobserved':'本地网络证据未观察到', 'control-disconnected':'节点控制连接断开', ready:'隧道已启动，等待外部验证',
    degraded:'隧道已启动，但数据连接异常', verified:'外部数据连接已验证', disabled:'未配置隧道 provider'
  } : {
    absent:'client not detected', starting:'connecting', 'local-not-ready':'local UDP not ready',
    'network-unobserved':'local network evidence was not observed', 'control-disconnected':'node control disconnected', ready:'proxy ready; external check pending',
    degraded:'proxy ready; data connection degraded', verified:'external data connection verified', disabled:'no tunnel provider configured'
  };
  return labels[tunnel.state] || tunnel.state || (currentLang === 'zh' ? '未知' : 'unknown');
}

function renderTunnelProof(tunnel) {
  const zh = currentLang === 'zh';
  const proof = $('tunnelProof');
  proof.className = `tunnel-proof ${escapeHtml(tunnel.level || 'warn')}`;
  $('tunnelProofTitle').textContent = t('tunnel.proofTitle');
  $('tunnelEndpoint').textContent = tunnel.externalEndpoint || (zh ? '未从日志识别远程地址' : 'remote endpoint not found');
  const steps = [
    [tunnel.localUdpReady, zh ? `本地 UDP ${tunnel.localPort || 8211} 正在监听` : `Local UDP ${tunnel.localPort || 8211} is listening`, 'localUdp'],
    [tunnel.processDetected, zh ? `${tunnel.provider || '隧道'} 进程存在` : `${tunnel.provider || 'Tunnel'} process detected`, 'process'],
    [tunnel.controlConnected, zh ? 'frpc 到节点的 TCP 控制连接已建立' : 'frpc node control connection established', 'control'],
    [tunnel.proxyReady, zh ? '服务日志确认 UDP 隧道启动成功' : 'Service log confirms proxy ready', 'proxy'],
    [tunnel.recentExternalTraffic, zh ? '检测到成功的外部数据连接' : 'Successful external data traffic detected', 'traffic']
  ];

  // Render horizontal step light bar
  $('tunnelProofBar').innerHTML = steps.map(([pass, label, key], i) => {
    const shortLabel = t('tunnel.step.' + key);
    return `<div class="proof-bar-step ${pass ? 'pass' : 'fail'}">
      <div class="proof-bar-dot">${pass ? '✓' : (i + 1)}</div>
      <div class="proof-bar-label">${escapeHtml(shortLabel)}</div>
    </div>`;
  }).join('');

  // Render detailed vertical steps (kept for accessibility)
  $('tunnelProofSteps').innerHTML = steps.map(([pass, label]) =>
    `<div class="proof-step ${pass ? 'pass' : 'fail'}"><span class="mark">${pass ? '✓' : '○'}</span><span>${escapeHtml(label)}</span></div>`
  ).join('');

  let error = '';
  const errorElement = $('tunnelLastError');
  errorElement.classList.remove('historical');
  if (tunnel.networkProbeObserved === false) {
    error = zh
      ? '本地网络证据探针超时或不可用；控制连接和 UDP 状态显示为“未观察到”，不会据此判定隧道已断开。'
      : 'The local network evidence probe timed out or was unavailable. Control and UDP are shown as unobserved, not disconnected.';
  } else if (tunnel.lastError) {
    const when = tunnel.lastErrorAt ? new Date(tunnel.lastErrorAt).toLocaleString() : '—';
    if (tunnel.lastErrorActive) {
      error = `${zh ? '最近异常' : 'Latest issue'} · ${when} · ${tunnel.lastError}`;
    } else {
      errorElement.classList.add('historical');
      error = `${zh ? '历史异常（当前控制连接正常）' : 'Historical issue (control connection is currently healthy)'} · ${when} · ${tunnel.lastError}`;
    }
  } else if (!tunnel.verifiedConnected) {
    error = zh
      ? '没有“朋友成功连入/外部流量成功”的证据，因此不会标记为已验证。'
      : 'No successful friend connection or external traffic evidence yet.';
  }
  errorElement.textContent = error;

  // Render anomaly timeline from tunnel-related incidents
  renderTunnelTimeline();
}

let tunnelIncidentCache = [];

async function loadTunnelIncidents() {
  try {
    const r = await api('/api/incidents?limit=50');
    if (r.ok && Array.isArray(r.incidents)) {
      const kw = /sakura|frp|frpc|tunnel|proxy|节点|隧道|control.*disconnect|visit.*start/i;
      tunnelIncidentCache = r.incidents.filter(it => {
        const txt = `${it.severity || ''} ${it.message || ''} ${it.raw || ''} ${it.source || ''}`;
        return kw.test(txt);
      });
    }
  } catch { /* ignore */ }
}

function renderTunnelTimeline() {
  const wrap = $('tunnelTimeline');
  const track = $('tunnelTimelineTrack');
  const title = $('tunnelTimelineTitle');
  const countEl = $('tunnelTimelineCount');
  if (!wrap || !track) return;
  title.textContent = t('tunnel.timelineTitle');
  const items = tunnelIncidentCache;
  if (!items.length) {
    wrap.style.display = 'none';
    return;
  }
  wrap.style.display = 'block';
  countEl.textContent = items.length.toString();
  track.innerHTML = items.map(item => {
    const sev = (item.severity || 'error').toLowerCase();
    const cls = sev.includes('warn') ? 'warn' : 'error';
    const when = item.loggedAt || item.observedAt || '';
    const timeStr = when ? new Date(when).toLocaleString() : '—';
    const msg = (item.message || item.raw || '').replace(/"/g, '&quot;').slice(0, 120);
    return `<div class="tunnel-timeline-dot ${cls}" data-tip="${timeStr} · ${msg}" title="${timeStr}"></div>`;
  }).join('');
}

function getPlayerField(player, fields) {
  if (!player || typeof player !== 'object') return '';
  for (const field of fields) {
    const value = player[field];
    if (value !== undefined && value !== null && String(value).trim()) return String(value).trim();
  }
  return '';
}

function renderPlayerCommandActions(player, playerIndex, privateMode) {
  const playerName = String(player?.name ?? player?.playerName ?? player?.playername ?? '—');
  const actions = [];
  const usedValues = new Set();
  for (const definition of PLAYER_COMMAND_ID_FIELDS) {
    const value = getPlayerField(player, definition.fields);
    if (!value || usedValues.has(value)) continue;
    usedValues.add(value);
    const candidateId = `player-${playerIndex}-${definition.kind}`;
    playerCommandCandidates.set(candidateId, { value, name: playerName, kindKey: definition.key });
    const kind = t(definition.key);
    const visibleId = privateMode ? maskIdentifier(value) : value;
    const label = `${t('rcon.playerPicker.use', { kind })}: ${playerName}${privateMode ? '' : ` (${visibleId})`}`;
    actions.push(`<button type="button" class="player-id-button" data-player-command-candidate="${escapeHtml(candidateId)}" aria-label="${escapeHtml(label)}" title="${escapeHtml(label)}"><span>${escapeHtml(kind)}</span><code>${escapeHtml(visibleId)}</code></button>`);
  }
  return actions.length ? `<div class="player-command-actions">${actions.join('')}</div>` : '—';
}

function insertPlayerIdIntoRcon(candidateId) {
  const candidate = playerCommandCandidates.get(candidateId);
  if (!candidate) {
    toast(t('rcon.playerPicker.unavailable'), 'error', t('rcon.error'));
    return;
  }
  const input = $('rconInput');
  const placeholder = /<(?:steamid|playeruid|playerid|userid)>/i.exec(input.value);
  if (placeholder) {
    input.setRangeText(candidate.value, placeholder.index, placeholder.index + placeholder[0].length, 'end');
  } else {
    const start = Number.isInteger(input.selectionStart) ? input.selectionStart : input.value.length;
    const end = Number.isInteger(input.selectionEnd) ? input.selectionEnd : start;
    const needsLeadingSpace = start === end && start > 0 && !/\s$/.test(input.value.slice(0, start));
    input.setRangeText(`${needsLeadingSpace ? ' ' : ''}${candidate.value}`, start, end, 'end');
  }
  activatePanel('rcon');
  requestAnimationFrame(() => input.focus());
  toast(t('rcon.playerPicker.inserted', { name: candidate.name, kind: t(candidate.kindKey) }), 'success');
}

function renderPlayerTable(players) {
  const privateMode = $('privacyToggle').checked;
  const zh = currentLang === 'zh';
  playerCommandCandidates = new Map();
  $('playersTableTitle').textContent = zh ? `在线玩家详情 · ${players.length}` : `Online Players · ${players.length}`;
  $('privacyToggleLabel').textContent = zh ? '隐藏敏感标识' : 'Mask identifiers';
  if (!players.length) {
    $('playerTableWrap').innerHTML = `<div class="empty-state">${zh ? '当前没有在线玩家' : 'No players online'}</div>`;
    return;
  }
  const rows = players.map((p, playerIndex) => {
    const uid = p.userId ?? p.userid ?? p.accountName ?? p.accountname ?? '';
    const pid = p.playerId ?? p.playerid ?? '';
    const ip = p.ip ?? '';
    return `<tr>
      <td>${escapeHtml(p.name ?? '—')}</td>
      <td>${escapeHtml(p.level ?? '—')}</td>
      <td>${escapeHtml(p.ping ?? '—')}</td>
      <td>${escapeHtml(privateMode ? maskIdentifier(uid) : (uid || '—'))}</td>
      <td>${escapeHtml(privateMode ? maskIdentifier(pid) : (pid || '—'))}</td>
      <td>${escapeHtml(privateMode ? maskIdentifier(ip) : (ip || '—'))}</td>
      <td>${escapeHtml(p.location_x ?? p.locationX ?? '—')}, ${escapeHtml(p.location_y ?? p.locationY ?? '—')}</td>
      <td>${renderPlayerCommandActions(p, playerIndex, privateMode)}</td>
    </tr>`;
  }).join('');
  $('playerTableWrap').innerHTML = `<table class="player-table">
    <thead><tr><th>${zh?'名称':'Name'}</th><th>${zh?'等级':'Level'}</th><th>Ping</th><th>User ID</th><th>Player ID</th><th>IP</th><th>${zh?'位置':'Location'}</th><th>${t('rcon.playerPicker.action')}</th></tr></thead>
    <tbody>${rows}</tbody>
  </table>`;
  $('playerTableWrap').querySelectorAll('[data-player-command-candidate]').forEach(button => {
    button.addEventListener('click', () => insertPlayerIdIntoRcon(button.dataset.playerCommandCandidate));
  });
}

function formatLastSeen(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '—';
  return d.toLocaleString();
}

function renderPlayerTimes(payload) {
  $('playerTimesTitle').textContent = t('playertimes.title');
  $('btnRefreshPlayerTimes').textContent = t('playertimes.refresh');
  const players = (payload && Array.isArray(payload.players)) ? payload.players : [];
  const updated = payload && (payload.lastObservedAt || payload.lastUpdated)
    ? formatLastSeen(payload.lastObservedAt || payload.lastUpdated) : '';
  const observationState = String((payload && payload.observationState) || 'unknown');
  const observationText = observationState === 'fresh'
    ? (updated ? `${t('playertimes.updated')} ${updated}` : '')
    : t('playertimes.stale');
  $('playerTimesUpdated').textContent = observationText;
  $('playerTimesUpdated').classList.toggle('stale', observationState !== 'fresh');
  if (!players.length) {
    $('playerTimesWrap').innerHTML = `<div class="empty-state">${t('playertimes.empty')}</div>`;
    return;
  }
  const sorted = players.slice().sort((a, b) => (Number(b.totalSeconds) || 0) - (Number(a.totalSeconds) || 0));
  const rows = sorted.map(p => {
    const name = escapeHtml(p.name || '—');
    const connectionState = String(p.connectionState || (p.isOnline ? 'online' : 'offline'));
    const total = formatDuration(p.totalSeconds);
    const session = connectionState === 'online' ? formatDuration(p.currentSessionSeconds) : '—';
    const count = Number(p.sessionCount) || 0;
    const last = connectionState === 'online' ? t('playertimes.online')
      : connectionState === 'unknown' ? t('playertimes.unknown') : formatLastSeen(p.lastSeen);
    const dotCls = connectionState === 'online' ? 'pt-online-dot'
      : connectionState === 'unknown' ? 'pt-online-dot unknown' : 'pt-online-dot offline';
    return `<tr>
      <td class="pt-name"><span class="${dotCls}"></span>${name}</td>
      <td class="pt-num">${escapeHtml(total)}</td>
      <td class="pt-num">${escapeHtml(session)}</td>
      <td class="pt-num">${count}</td>
      <td class="pt-num">${escapeHtml(last)}</td>
    </tr>`;
  }).join('');
  $('playerTimesWrap').innerHTML = `<table class="player-times-table">
    <thead><tr>
      <th>${t('playertimes.name')}</th>
      <th>${t('playertimes.total')}</th>
      <th>${t('playertimes.session')}</th>
      <th>${t('playertimes.count')}</th>
      <th>${t('playertimes.last')}</th>
    </tr></thead>
    <tbody>${rows}</tbody>
  </table>`;
}

async function refreshPlayerTimes() {
  try {
    const payload = await api('/api/player-times');
    playerTimesCache = payload;
    renderPlayerTimes(payload);
  } catch (e) {
    if ($('playerTimesWrap')) {
      $('playerTimesWrap').innerHTML = `<div class="empty-state">${escapeHtml(e.message || 'load failed')}</div>`;
    }
  }
}

function dashboardWarningText(message) {
  if (currentLang !== 'zh') return message;
  if (/is running, but a newer data-connection error/.test(message)) {
    return '隧道 Provider 已经启动，但服务日志中存在更新的数据连接错误。';
  }
  if (/is not ready:/.test(message)) {
    const state = message.split(':').slice(1).join(':').trim().replace(/\.$/, '');
    const labels = {
      absent: '未检测到客户端',
      starting: '正在建立连接',
      'local-not-ready': '本地 UDP 未监听',
      'control-disconnected': '节点控制连接断开',
      ready: '隧道已启动，等待外部验证',
      degraded: '隧道数据连接异常',
      verified: '外部数据连接已验证'
    };
    return `隧道 Provider 尚未就绪：${labels[state] || state}。`;
  }
  if (/Container is not fully running/.test(message)) return '容器尚未完全运行。';
  if (/Container health is/.test(message)) return `容器健康状态异常：${message.replace(/^.*? is /, '')}`;
  if (/Palworld REST status is unavailable/.test(message)) return 'Palworld REST 状态不可访问。';
  if (/container was OOM-killed/i.test(message)) return '容器曾因内存不足被系统终止。';
  if (/Scheduled backups are enabled/.test(message)) return '已启用定时备份，但当前没有备份归档。';
  if (/REST API is disabled/.test(message)) return 'REST API 已禁用，仪表盘与主要管理操作会受限。';
  if (/Recent container logs contain/.test(message)) {
    return message.replace('Recent container logs contain', '最近容器日志包含')
      .replace('critical and', '条严重、')
      .replace('error entries.', '条错误记录。');
  }
  if (message === 'Daily log archive collector is not running.') {
    return '每日日志归档器未运行；历史文件仍保留，但新日志不会自动刷新。';
  }
  return message;
}

function updateStateLabel(update) {
  const state = String(update?.state || 'not-observed');
  const keyByState = {
    'not-applicable': 'update.state.unsupported',
    'not-observed': 'update.state.unobserved'
  };
  const key = keyByState[state] || `update.state.${state}`;
  return t(key);
}

function renderUpdateStatus(update) {
  const el = $('updateStatus');
  if (!el) return;
  const state = String(update?.state || 'not-observed');
  const isUpdating = state === 'updating';
  const hasProgress = isUpdating && Number.isFinite(Number(update?.progressPercent));
  const percent = hasProgress ? Math.max(0, Math.min(100, Number(update.progressPercent))) : 0;
  const version = update?.gameVersion ? String(update.gameVersion) : '';
  const downloaded = Number(update?.downloadedBytes);
  const total = Number(update?.totalBytes);
  let noteKey = 'update.note.unobserved';
  if (isUpdating) noteKey = 'update.note.updating';
  else if (state === 'completed') noteKey = 'update.note.completed';
  else if (state === 'disabled') noteKey = 'update.note.disabled';
  else if (state === 'not-applicable') noteKey = 'update.note.unsupported';

  const progressText = hasProgress
    ? `${percent.toFixed(2)}%${Number.isFinite(downloaded) && Number.isFinite(total) && total > 0 ? ` · ${formatBytes(downloaded)} / ${formatBytes(total)}` : ''}`
    : (isUpdating ? '—' : '');
  const ariaProgress = hasProgress
    ? `aria-valuenow="${percent.toFixed(2)}"`
    : `aria-valuetext="${escapeHtml(t('update.progress.unavailable'))}"`;
  const fillClass = state === 'failed' ? 'danger' : state === 'updating' ? 'warn' : '';
  const autoKey = typeof update?.automaticOnBoot === 'boolean'
    ? (update.automaticOnBoot ? 'update.auto.on' : 'update.auto.off')
    : 'update.auto.unknown';
  el.innerHTML = `
    <div class="update-status-head">
      <span class="update-status-label">${escapeHtml(updateStateLabel(update))}</span>
      <span class="update-status-version">${escapeHtml(version)}</span>
    </div>
    ${isUpdating ? `<div class="update-progress-track" role="progressbar" aria-label="${escapeHtml(t('update.title'))}" aria-valuemin="0" aria-valuemax="100" ${ariaProgress}><div class="update-progress-fill ${fillClass}" style="width:${percent.toFixed(2)}%"></div></div>` : ''}
    <div class="update-status-meta">${escapeHtml(isUpdating ? progressText : t(autoKey))}</div>
    <div class="update-status-note">${escapeHtml(t(noteKey))}</div>`;
}

let updateFallbackState = null;
let updateFallbackCheckedAt = 0;

function parseStartupUpdateLogs(logText, automaticOnBoot) {
  const result = {
    supported: true,
    automaticOnBoot,
    state: 'not-observed',
    phase: '',
    progressPercent: null,
    downloadedBytes: null,
    totalBytes: null,
    gameVersion: ''
  };
  let lastActive = -1;
  let lastSuccess = -1;
  let lastError = -1;
  String(logText || '').split('\n').forEach((line, index) => {
    const progress = line.match(/Update state \(0x[0-9A-Fa-f]+\) ([^,]+), progress:\s*([\d.]+)\s*\(([\d,]+)\s*\/\s*([\d,]+)\)/);
    if (progress) {
      lastActive = index;
      result.phase = progress[1].trim();
      result.progressPercent = Number(progress[2]);
      result.downloadedBytes = Number(progress[3].replaceAll(',', ''));
      result.totalBytes = Number(progress[4].replaceAll(',', ''));
    }
    if (/Success! App '2394010' fully installed\./.test(line)) lastSuccess = index;
    if (/(steamcmd|update).*(error|failed)|(error|failed).*steamcmd/i.test(line)) lastError = index;
    const version = line.match(/Game version is (v[^\s]+)/);
    if (version) result.gameVersion = version[1];
  });
  if (lastActive > lastSuccess) result.state = 'updating';
  else if (lastSuccess >= 0) result.state = 'completed';
  else if (lastError >= 0) result.state = 'failed';
  return result;
}

async function refreshUpdateStatusFallback() {
  if (dashboardState?.services?.update) return;
  const now = Date.now();
  const interval = updateFallbackState?.state === 'updating' ||
    updateFallbackState?.state === 'not-observed' ||
    typeof updateFallbackState?.automaticOnBoot !== 'boolean' ? 5000 : 60000;
  if (now - updateFallbackCheckedAt < interval) return;
  updateFallbackCheckedAt = now;
  const payload = await api('/api/logs?lines=1200');
  const rawAuto = String(envValues?.UPDATE_ON_BOOT || '').toLowerCase();
  const automaticOnBoot = rawAuto ? rawAuto === 'true' : null;
  updateFallbackState = parseStartupUpdateLogs(payload.logs, automaticOnBoot);
  renderUpdateStatus(updateFallbackState);
}

function activeRuntimeFromState(s) {
  const r = s && s.runtime && s.runtime.runtime ? s.runtime.runtime : {};
  return String(r.active || 'docker');
}

function runtimeActiveLabel(runtimeInfo) {
  const active = activeRuntimeFromState({ runtime: runtimeInfo });
  if (currentLang === 'zh') {
    return active === 'windows' ? 'Windows 原生' : active === 'none' ? '无运行时' : 'Docker';
  }
  return active === 'windows' ? 'Windows native' : active === 'none' ? 'no runtime' : 'Docker';
}

function renderDashboard(s) {
  const c = s.container || {};
  const m = s.metrics || {};
  const server = s.server || {};
  const services = s.services || {};
  const storage = s.storage || {};
  const zh = currentLang === 'zh';
  const status = c.status || 'unknown';
  const isWin = activeRuntimeFromState(s) === 'windows';

  $('statusDot').className = 'status-dot ' + status;
  $('statusText').textContent = t(STATUS_KEY_MAP[status] || 'status.unknown');
  $('statStatus').textContent = t(STATUS_KEY_MAP[status] || 'status.unknown');
  $('statHealth').textContent = isWin
    ? `health: ${c.health || '—'} · ${zh?'PID':'pid'} ${c.pid || '—'}`
    : `health: ${c.health || '—'} · ${zh?'重启':'restarts'} ${numberOr(c.restartCount)}`;

  const players = numberOr(m.currentplayernum);
  const maxPlayers = numberOr(m.maxplayernum);
  $('statPlayers').textContent = players;
  $('statMaxPlayers').textContent = maxPlayers || '—';
  $('statPlayersBar').style.width = `${Math.min(100, maxPlayers ? players / maxPlayers * 100 : 0)}%`;
  $('statFps').textContent = numberOr(m.serverfps).toFixed(0);
  $('statFpsAverage').textContent = `avg ${numberOr(m.serverfpsaverage).toFixed(1)}`;
  $('statFrameTime').textContent = numberOr(m.serverframetime).toFixed(1);
  $('statWorldDay').textContent = numberOr(m.days);
  $('statWorldDayDetail').textContent = zh ? `第 ${numberOr(m.days)} 天` : `day ${numberOr(m.days)}`;
  $('statBaseCamps').textContent = numberOr(m.basecampnum);
  $('statBaseCampsDetail').textContent = zh ? `${numberOr(m.basecampnum)} 个基地` : `${numberOr(m.basecampnum)} camps`;
  $('statStartedAt').textContent = c.startedAt ? `${zh?'启动于':'started'} ${new Date(c.startedAt).toLocaleString()}` : 'started —';

  const rawCpuPct = Math.max(0, numberOr(c.cpuPct));
  const cpuLimit = Math.max(0.01, numberOr(c.cpuLimit, 6));
  // Docker reports 100% per logical CPU (0-600% for 6 cores), so divide by
  // cpuLimit to normalize. Windows PalServer reports an already-normalized
  // 0-100% value relative to total CPU capacity — no division needed.
  const allocatedCpuPct = Math.min(100, isWin ? rawCpuPct : rawCpuPct / cpuLimit);
  $('statCpu').textContent = allocatedCpuPct.toFixed(1);
  $('statCpuCapacity').textContent = isWin
    ? (zh ? `${cpuLimit} 核主机 · 进程 ${rawCpuPct.toFixed(1)}%` : `${cpuLimit} core host · process ${rawCpuPct.toFixed(1)}%`)
    : (zh ? `${cpuLimit} 核配额 · Docker 原始 ${rawCpuPct.toFixed(1)}%` : `${cpuLimit} core allocation · Docker raw ${rawCpuPct.toFixed(1)}%`);
  $('statCpuBar').style.width = `${allocatedCpuPct}%`;
  $('statCpuBar').className = 'stat-bar-fill' + (allocatedCpuPct > 80 ? ' danger' : allocatedCpuPct > 60 ? ' warn' : '');
  $('statCpuRing').style.setProperty('--ring-value', allocatedCpuPct.toFixed(2));
  $('statCpuRing').className = 'resource-ring' + (allocatedCpuPct > 80 ? ' danger' : allocatedCpuPct > 60 ? ' warn' : '');
  $('statCpuRingValue').textContent = `${allocatedCpuPct.toFixed(1)}%`;
  $('statCpuRing').setAttribute('aria-label', t(
    isWin ? 'stat.cpu.ring.windows' : 'stat.cpu.ring.docker',
    { cores: cpuLimit.toFixed(0), pct: allocatedCpuPct.toFixed(1) }
  ));
  const memPct = Math.max(0, numberOr(c.memoryPct));
  const allocatedMemPct = Math.min(100, memPct);
  const memoryLimitMb = numberOr(c.memoryLimitMb);
  $('statMem').textContent = numberOr(c.memoryMb).toFixed(0);
  $('statMemLimit').textContent = memoryLimitMb.toFixed(0);
  $('statMemCapacity').textContent = zh
    ? `已用 ${allocatedMemPct.toFixed(1)}% · 容量 ${(memoryLimitMb / 1024).toFixed(1)} GiB`
    : `${allocatedMemPct.toFixed(1)}% used · ${(memoryLimitMb / 1024).toFixed(1)} GiB capacity`;
  $('statMemBar').style.width = `${allocatedMemPct}%`;
  $('statMemBar').className = 'stat-bar-fill memory' + (memPct > 80 ? ' danger' : memPct > 60 ? ' warn' : '');
  $('statMemRing').style.setProperty('--ring-value', allocatedMemPct.toFixed(2));
  $('statMemRing').className = 'resource-ring memory' + (allocatedMemPct > 80 ? ' danger' : allocatedMemPct > 60 ? ' warn' : '');
  $('statMemRingValue').textContent = `${allocatedMemPct.toFixed(1)}%`;
  $('statMemRing').setAttribute('aria-label', zh
    ? `内存配额占用 ${allocatedMemPct.toFixed(1)}%`
    : `Memory allocation usage ${allocatedMemPct.toFixed(1)}%`);

  const uptime = formatDuration(m.uptime);
  $('statServerUptime').textContent = uptime;
  $('metaUptime').textContent = uptime;
  $('serverIdentityName').textContent = server.servername || 'Palworld Server';
  $('serverIdentityMeta').textContent = `${server.version || 'version —'} · ${server.description || (zh?'无描述':'no description')} · world ${server.worldguid || '—'}`;
  $('dashboardFreshness').textContent = `${zh?'状态采样':'sampled'} ${new Date(s.generatedAt).toLocaleTimeString()} · ${runtimeActiveLabel(s.runtime)} · REST${activeRuntimeFromState(s) === 'windows' ? '' : ' + Docker'}`;

  const warnings = Array.isArray(s.warnings) ? s.warnings : [];
  $('dashboardWarnings').classList.toggle('show', warnings.length > 0);
  $('dashboardWarnings').innerHTML = warnings.length
    ? `<strong>${zh?'需要注意':'Attention'}</strong><ul>${warnings.map(w => `<li>${escapeHtml(dashboardWarningText(w))}</li>`).join('')}</ul>`
    : '';

  const rest = services.rest || {};
  const rcon = services.rcon || {};
  const management = services.management || {};
  const tunnel = services.tunnel || {};
  const backup = services.backup || {};
  const dailyLogs = services.dailyLogArchive || {};
  const mods = services.modManager || {};
  // Older panel processes do not yet return services.update. Keep the latest
  // browser-side log parse instead of replacing it with an empty state on each
  // five-second dashboard poll.
  renderUpdateStatus(services.update || updateFallbackState || {});
  $('serviceTitle').textContent = zh ? '服务与端口' : 'Services & Ports';
  $('btnCheckTunnel').textContent = zh ? '验证隧道' : 'Verify tunnel';
  $('serviceList').innerHTML = [
    serviceRow('REST API', rest.reachable ? `${zh?'可访问':'reachable'} · ${rest.port || '—'}` : (zh?'不可访问':'unreachable'), rest.reachable ? 'ok' : 'danger'),
    serviceRow('RCON', rcon.configured ? `${rcon.port || '—'} · localhost` : (zh?'已禁用':'disabled'), rcon.configured ? 'warn' : ''),
    serviceRow(zh ? `隧道 · ${tunnel.provider || 'none'}` : `Tunnel · ${tunnel.provider || 'none'}`, tunnelStateLabel(tunnel), tunnel.state === 'disabled' ? 'warn' : (tunnel.level || 'danger')),
    serviceRow(zh?'定时备份':'Backups', backup.configured ? `${backup.count || 0} · ${backup.totalSizeMb || 0} MB` : (zh?'已禁用':'disabled'), backup.configured ? 'ok' : 'warn'),
    serviceRow(zh?'每日日志':'Daily logs', dailyLogs.running
      ? `${zh?'运行中':'running'} · ${dailyLogs.count || 0} TXT`
      : (zh?'未运行':'not running'), dailyLogs.running ? 'ok' : 'warn'),
    serviceRow('Mod Manager', mods.enabled ? (zh?'启用':'enabled') : `${zh?'预留/禁用':'reserved/disabled'} · ${mods.installed || 0}`, ''),
    serviceRow(isWin ? (zh?'运行时健康':'Runtime health') : (zh?'容器健康':'Container health'), `${c.health || 'unknown'}${c.oomKilled ? ' · OOM' : ''}`, c.health === 'healthy' && !c.oomKilled ? 'ok' : 'warn')
  ].join('');
  const legacyRconBlock = $('legacyRconBlock');
  if (legacyRconBlock) legacyRconBlock.style.display = rcon.configured ? '' : 'none';
  renderTunnelProof(tunnel);

  const save = storage.saves || {};
  const imageName = String(c.image || '—').replace(/^.*\//, '');
  $('runtimeTitle').textContent = zh ? '运行与存储' : 'Runtime & Storage';
  $('runtimeList').innerHTML = [
    serviceRow(isWin ? (zh?'运行时':'Runtime') : (zh?'镜像':'Image'), isWin ? runtimeActiveLabel(s.runtime) : imageName, ''),
    serviceRow(isWin ? (zh?'主机硬件':'Host hardware') : (zh?'资源限制':'Limits'), `${c.cpuLimit || 6} CPU · ${(numberOr(c.memoryLimitMb)/1024).toFixed(1)} GiB`, ''),
    serviceRow(zh?'存档文件':'Save files', `${save.fileCount || 0} · ${save.sizeMb || 0} MB`, ''),
    serviceRow(zh?'最近写入':'Latest write', save.latestWrite || '—', ''),
    serviceRow(zh?'退出码':'Exit code', String(c.exitCode ?? '—'), c.exitCode === 0 ? 'ok' : 'warn')
  ].join('');

  renderPlayerTable(Array.isArray(s.players) ? s.players : []);

  // FPS history chart
  updateFpsChart(numberOr(m.serverfps), numberOr(m.serverfpsaverage));
  // CPU / memory trend charts (separate)
  updateCpuChart(allocatedCpuPct);
  updateMemChart(allocatedMemPct);
}

// FPS chart state
const fpsHistory = [];
const FPS_HISTORY_MAX = 60;
let fpsChartCtx = null;
let fpsChartDpr = 1;

function updateFpsChart(currentFps, avgFps) {
  fpsHistory.push({ fps: currentFps, avg: avgFps, t: Date.now() });
  if (fpsHistory.length > FPS_HISTORY_MAX) fpsHistory.shift();
  drawFpsChart();
  const zh = currentLang === 'zh';
  $('fpsLegendCurrent').textContent = (zh ? '当前 ' : 'now ') + Math.round(currentFps);
  $('fpsLegendAvg').textContent = (zh ? '平均 ' : 'avg ') + Math.round(avgFps);
}

function resetFpsChartContext() {
  fpsChartCtx = null;
  if (fpsHistory.length) drawFpsChart();
}

function drawFpsChart() {
  const canvas = $('fpsChart');
  if (!canvas) return;
  const dpr = window.devicePixelRatio || 1;
  // Re-sync bitmap to current CSS size when DPR or layout changed.
  const rect = canvas.getBoundingClientRect();
  const cssW = Math.max(1, Math.floor(rect.width));
  const cssH = Math.max(1, Math.floor(rect.height));
  if (!fpsChartCtx || fpsChartDpr !== dpr || canvas.width !== cssW * dpr || canvas.height !== cssH * dpr) {
    canvas.width = cssW * dpr;
    canvas.height = cssH * dpr;
    fpsChartCtx = canvas.getContext('2d');
    fpsChartCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
    fpsChartDpr = dpr;
  }
  const ctx = fpsChartCtx;
  const w = cssW;
  const h = cssH;
  const isDark = document.documentElement.getAttribute('data-theme') !== 'light';
  const accentColor = isDark ? '#4ade80' : '#16a34a';
  const dimColor = isDark ? '#5a6478' : '#9ca3af';
  const gridColor = isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)';
  const textColor = isDark ? '#8a93a6' : '#6b7280';

  ctx.clearRect(0, 0, w, h);

  if (fpsHistory.length < 2) {
    ctx.fillStyle = textColor;
    ctx.font = '12px ' + getComputedStyle(document.body).fontFamily;
    ctx.textAlign = 'center';
    ctx.fillText(currentLang === 'zh' ? '采集数据中…' : 'Collecting data…', w / 2, h / 2);
    return;
  }

  // Determine Y range (0 to max observed * 1.2, at least 60)
  const allFps = fpsHistory.map(p => Math.max(p.fps, p.avg));
  const maxFps = Math.max(60, Math.ceil(Math.max(...allFps) * 1.2 / 10) * 10);
  const padL = 32, padR = 8, padT = 8, padB = 18;
  const plotW = w - padL - padR;
  const plotH = h - padT - padB;

  // Grid lines + Y labels
  ctx.strokeStyle = gridColor;
  ctx.lineWidth = 1;
  ctx.fillStyle = textColor;
  ctx.font = '10px monospace';
  ctx.textAlign = 'right';
  for (let v = 0; v <= maxFps; v += Math.ceil(maxFps / 4 / 10) * 10) {
    const y = padT + plotH - (v / maxFps) * plotH;
    ctx.beginPath();
    ctx.moveTo(padL, y);
    ctx.lineTo(w - padR, y);
    ctx.stroke();
    ctx.fillText(String(v), padL - 4, y + 3);
  }

  // Plot FPS line
  const xStep = plotW / (FPS_HISTORY_MAX - 1);
  ctx.strokeStyle = accentColor;
  ctx.lineWidth = 1.8;
  ctx.beginPath();
  fpsHistory.forEach((p, i) => {
    const x = padL + i * xStep;
    const y = padT + plotH - (p.fps / maxFps) * plotH;
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  });
  ctx.stroke();

  // Fill area under FPS line
  ctx.lineTo(padL + (fpsHistory.length - 1) * xStep, padT + plotH);
  ctx.lineTo(padL, padT + plotH);
  ctx.closePath();
  ctx.fillStyle = accentColor + (isDark ? '22' : '20');
  ctx.fill();

  // Average line (dashed)
  const avgVal = fpsHistory[fpsHistory.length - 1].avg;
  if (avgVal > 0) {
    const avgY = padT + plotH - (avgVal / maxFps) * plotH;
    ctx.strokeStyle = dimColor;
    ctx.lineWidth = 1;
    ctx.setLineDash([4, 3]);
    ctx.beginPath();
    ctx.moveTo(padL, avgY);
    ctx.lineTo(w - padR, avgY);
    ctx.stroke();
    ctx.setLineDash([]);
  }
}

$('privacyToggle').addEventListener('change', () => {
  if (dashboardState) renderPlayerTable(Array.isArray(dashboardState.players) ? dashboardState.players : []);
});

// Re-sync chart bitmaps on window resize / DPR change.
function resetAllChartContexts() {
  resetFpsChartContext();
  resetCpuChartContext();
  resetMemChartContext();
}
let fpsResizeTimer = null;
window.addEventListener('resize', () => {
  if (fpsResizeTimer) clearTimeout(fpsResizeTimer);
  fpsResizeTimer = setTimeout(resetAllChartContexts, 120);
});

// ===== Resource trend charts (CPU / memory, separate) =====
const cpuHistory = [];
const memHistory = [];
const RES_HISTORY_MAX = 60;
let cpuChartCtx = null, cpuChartDpr = 1;
let memChartCtx = null, memChartDpr = 1;

function updateCpuChart(cpuPct) {
  const v = Math.max(0, Math.min(100, cpuPct));
  cpuHistory.push({ v, t: Date.now() });
  if (cpuHistory.length > RES_HISTORY_MAX) cpuHistory.shift();
  drawPercentChart('cpuChart', cpuHistory, cpuChartCtx, cpuChartDpr, (ctx, dpr) => { cpuChartCtx = ctx; cpuChartDpr = dpr; }, 'cpu');
  const zh = currentLang === 'zh';
  const avg = cpuHistory.reduce((s, p) => s + p.v, 0) / cpuHistory.length;
  $('cpuLegendCurrent').textContent = (zh ? '当前 ' : 'now ') + v.toFixed(1) + '%';
  $('cpuLegendAvg').textContent = (zh ? '平均 ' : 'avg ') + avg.toFixed(1) + '%';
}
function updateMemChart(memPct) {
  const v = Math.max(0, Math.min(100, memPct));
  memHistory.push({ v, t: Date.now() });
  if (memHistory.length > RES_HISTORY_MAX) memHistory.shift();
  drawPercentChart('memChart', memHistory, memChartCtx, memChartDpr, (ctx, dpr) => { memChartCtx = ctx; memChartDpr = dpr; }, 'mem');
  const zh = currentLang === 'zh';
  const avg = memHistory.reduce((s, p) => s + p.v, 0) / memHistory.length;
  $('memLegendCurrent').textContent = (zh ? '当前 ' : 'now ') + v.toFixed(1) + '%';
  $('memLegendAvg').textContent = (zh ? '平均 ' : 'avg ') + avg.toFixed(1) + '%';
}

function resetCpuChartContext() { cpuChartCtx = null; if (cpuHistory.length) updateCpuChart(cpuHistory[cpuHistory.length - 1].v); else drawPercentChart('cpuChart', cpuHistory, cpuChartCtx, cpuChartDpr, (ctx, dpr) => { cpuChartCtx = ctx; cpuChartDpr = dpr; }, 'cpu'); }
function resetMemChartContext() { memChartCtx = null; if (memHistory.length) updateMemChart(memHistory[memHistory.length - 1].v); else drawPercentChart('memChart', memHistory, memChartCtx, memChartDpr, (ctx, dpr) => { memChartCtx = ctx; memChartDpr = dpr; }, 'mem'); }

function drawPercentChart(canvasId, history, ctxRef, dprRef, saveCtx, kind) {
  const canvas = $(canvasId);
  if (!canvas) return;
  const dpr = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  const cssW = Math.max(1, Math.floor(rect.width));
  const cssH = Math.max(1, Math.floor(rect.height));
  if (!ctxRef || dprRef !== dpr || canvas.width !== cssW * dpr || canvas.height !== cssH * dpr) {
    canvas.width = cssW * dpr;
    canvas.height = cssH * dpr;
    ctxRef = canvas.getContext('2d');
    ctxRef.setTransform(dpr, 0, 0, dpr, 0, 0);
    dprRef = dpr;
    saveCtx(ctxRef, dprRef);
  }
  const ctx = ctxRef;
  const w = cssW, h = cssH;
  const isDark = document.documentElement.getAttribute('data-theme') !== 'light';
  // CPU = warn (orange), Memory = info (blue), FPS = accent (green)
  const lineColor = kind === 'cpu'
    ? (isDark ? '#f97316' : '#ea580c')
    : (isDark ? '#60a5fa' : '#2563eb');
  const gridColor = isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)';
  const textColor = isDark ? '#8a93a8' : '#6b7280';

  ctx.clearRect(0, 0, w, h);

  if (history.length < 2) {
    ctx.fillStyle = textColor;
    ctx.font = '12px ' + getComputedStyle(document.body).fontFamily;
    ctx.textAlign = 'center';
    ctx.fillText(currentLang === 'zh' ? '采集数据中…' : 'Collecting data…', w / 2, h / 2);
    return;
  }

  const dataMax = Math.max(...history.map(p => p.v), 0);
  // Dynamic Y-axis: if data stays well below 100%, zoom in to reveal trends.
  // Round up to the nearest "nice" number. Keep a minimum range of 5%.
  let maxVal;
  if (dataMax >= 85) {
    maxVal = 100;
  } else if (dataMax >= 1) {
    // Round up to nearest 10, but at least 10
    maxVal = Math.max(10, Math.ceil((dataMax + 2) / 10) * 10);
  } else {
    maxVal = 5;
  }
  const padL = 32, padR = 8, padT = 8, padB = 18;
  const plotW = w - padL - padR;
  const plotH = h - padT - padB;

  ctx.strokeStyle = gridColor;
  ctx.lineWidth = 1;
  ctx.fillStyle = textColor;
  ctx.font = '10px monospace';
  ctx.textAlign = 'right';
  // Draw 5 grid lines (0, 25%, 50%, 75%, 100% of maxVal)
  for (let i = 0; i <= 4; i++) {
    const v = (maxVal * i) / 4;
    const y = padT + plotH - (v / maxVal) * plotH;
    ctx.beginPath();
    ctx.moveTo(padL, y);
    ctx.lineTo(w - padR, y);
    ctx.stroke();
    ctx.fillText(v.toFixed(maxVal < 10 ? 1 : 0) + '%', padL - 4, y + 3);
  }

  const xStep = plotW / (RES_HISTORY_MAX - 1);
  ctx.strokeStyle = lineColor;
  ctx.lineWidth = 1.8;
  ctx.beginPath();
  history.forEach((p, i) => {
    const x = padL + i * xStep;
    const y = padT + plotH - (Math.min(p.v, maxVal) / maxVal) * plotH;
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  });
  ctx.stroke();
  ctx.lineTo(padL + (history.length - 1) * xStep, padT + plotH);
  ctx.lineTo(padL, padT + plotH);
  ctx.closePath();
  ctx.fillStyle = lineColor + (isDark ? '22' : '20');
  ctx.fill();

  // If zoomed in, show a small range indicator in the top-right corner
  if (maxVal < 100) {
    ctx.fillStyle = textColor;
    ctx.font = '9px monospace';
    ctx.textAlign = 'right';
    ctx.fillText('0-' + maxVal + '%', w - padR - 2, padT + 9);
  }
}

// ===== Clock =====
function tickClock() {
  const d = new Date();
  $('metaTime').textContent = d.toLocaleTimeString(currentLang === 'zh' ? 'zh-CN' : 'en-GB');
}
setInterval(tickClock, 1000);
tickClock();

// ===== Overview actions =====
async function checkTunnel() {
  const button = $('btnCheckTunnel');
  button.disabled = true;
  button.textContent = currentLang === 'zh' ? '正在核验…' : 'Checking…';
  try {
    const tunnel = await api('/api/tunnel/check', {method: 'POST'});
    if (dashboardState) {
      dashboardState.services ||= {};
      dashboardState.services.tunnel = tunnel;
      renderDashboard(dashboardState);
    } else {
      renderTunnelProof(tunnel);
    }
    const message = tunnelStateLabel(tunnel);
    toast(message, tunnel.verifiedConnected ? 'success' : 'warn', currentLang === 'zh' ? '隧道核验' : 'Tunnel check');
    // Refresh anomaly timeline after a tunnel check
    loadTunnelIncidents().then(renderTunnelTimeline).catch(() => {});
  } catch (e) {
    toast(e.message, 'error', currentLang === 'zh' ? '隧道核验失败' : 'Tunnel check failed');
  } finally {
    button.disabled = false;
    button.textContent = currentLang === 'zh' ? '验证隧道' : 'Verify tunnel';
  }
}

async function saveWorld() {
  showLoading(t('loading.saving'));
  try {
    const r = await api('/api/save', { method: 'POST' });
    if (r.ok) toast(t('toast.worldSaved'), 'success', t('toast.ok'));
    else toast(r.error || t('common.error'), 'error', t('rcon.error'));
  } catch (e) { toast(e.message, 'error', t('common.networkError')); }
  hideLoading();
}

function focusPlayerTable() {
  const target = $('playerTableWrap');
  activatePanel('overview');
  target.setAttribute('tabindex', '-1');
  target.scrollIntoView({ behavior: 'smooth', block: 'center' });
  requestAnimationFrame(() => target.focus({ preventScroll: true }));
}

$('btnCheckTunnel').addEventListener('click', checkTunnel);

$('btnRestart').addEventListener('click', async () => {
  const ok = await showModal(t('modal.restart.title'), t('modal.restart.body'));
  if (!ok) return;
  showLoading(t('loading.restarting'));
  try {
    const r = await api('/api/restart', { method: 'POST' });
    if (r.ok) { toast(t('toast.containerRestarted'), 'success', t('toast.ok')); refreshState(); }
    else toast(r.error || t('common.error'), 'error', t('common.error'));
  } catch (e) { toast(e.message, 'error', t('common.networkError')); }
  hideLoading();
});

$('btnSave').addEventListener('click', saveWorld);

$('btnBackupNow').addEventListener('click', () => doBackup());
$('btnBackupPanel').addEventListener('click', () => doBackup());

async function doBackup() {
  showLoading(t('loading.backup'));
  try {
    const r = await api('/api/backup', { method: 'POST' });
    if (r.ok) { toast(t('toast.backupCreated'), 'success', t('toast.ok')); loadBackups(); }
    else toast(r.error || t('common.error'), 'error', t('backup.error'));
  } catch (e) { toast(e.message, 'error', t('common.networkError')); }
  hideLoading();
}

$('btnStop').addEventListener('click', async () => {
  const ok = await showModal(t('modal.stop.title'), t('modal.stop.body'));
  if (!ok) return;
  showLoading(t('loading.stopping'));
  try {
    const r = await api('/api/stop', { method: 'POST' });
    setTimeout(refreshState, 1000);
    if (r.ok) toast(t('toast.stopSignal'), 'success');
    else toast(r.error || t('common.error'), 'error', t('common.error'));
  } catch (e) { toast(e.message, 'error', t('common.networkError')); }
  hideLoading();
});

$('btnRefreshLogs').addEventListener('click', loadMiniLog);
$('btnRefreshPlayerTimes').addEventListener('click', () => refreshPlayerTimes());

document.querySelectorAll('[data-guide-action]').forEach(button => {
  button.addEventListener('click', () => {
    switch (button.dataset.guideAction) {
      case 'save': saveWorld(); break;
      case 'backup': doBackup(); break;
      case 'players': focusPlayerTable(); break;
      case 'tunnel': checkTunnel(); break;
      case 'logs': activatePanel('logs'); break;
    }
  });
});

// ===== Logs =====
const LOG_EXPLANATIONS = {
  zh: {
    activity:'普通运行记录，未匹配到已知异常模式。',
    startupActivity:'正常启动或资源加载信息，通常不需要处理。',
    restAccess:'REST API 请求成功；通常是仪表盘在读取服务器信息、指标或玩家列表。',
    gracefulStop:'服务端收到了正常停止信号，正在保存并退出。',
    backupComplete:'备份操作已完成。',
    backupFailed:'备份失败，存档仍可能正常，但当前没有生成新的保护副本。',
    diskFull:'磁盘空间不足，可能导致存档、备份或更新失败。',
    outOfMemory:'进程或容器内存不足，存在崩溃和存档中断风险。',
    portInUse:'需要监听的端口已被其他进程占用。',
    permissionDenied:'容器或脚本没有访问目标文件、目录或端口的权限。',
    saveProblem:'日志提示存档损坏、无效或加载失败，先保护现有文件。',
    connectionRefused:'目标服务主动拒绝连接，通常表示服务未启动或端口不一致。',
    timeout:'操作等待超时，常见原因是网络不稳定、目标无响应或资源拥塞。',
    updateActivity:'SteamCMD 或容器正在检查、下载或安装更新。',
    playerJoined:'检测到玩家加入或登录记录。',
    playerLeft:'检测到玩家离开或断线记录。',
    deprecated:'正在使用已弃用功能；当前可能可用，但后续版本可能移除。',
    tunnelIoTimeout:'隧道 Provider 建立新的数据连接时超时：控制连接和隧道配置可能仍正常，但这次转发没有建立成功。',
    tunnelConnectionFailed:'隧道 Provider 的节点、控制连接或本地服务转发失败。',
    serverCrash:'检测到崩溃、致命错误或未处理异常。',
    genericError:'检测到错误关键词，但规则无法进一步确定原因；需要结合前后日志判断。',
    genericWarning:'检测到警告关键词；不一定影响运行，但应结合重复频率判断。'
  },
  en: {
    activity:'Normal activity; no known anomaly pattern matched.',
    startupActivity:'Normal startup or resource loading activity.',
    restAccess:'The REST API request succeeded; this is usually a dashboard status query.',
    gracefulStop:'The server received a normal stop signal and is exiting gracefully.',
    backupComplete:'The backup completed.',
    backupFailed:'The backup failed; no new recovery archive was produced.',
    diskFull:'Disk space is exhausted and saves, backups, or updates may fail.',
    outOfMemory:'The process or container ran out of memory.',
    portInUse:'A required listening port is already in use.',
    permissionDenied:'The process lacks permission for a file, directory, or port.',
    saveProblem:'The save appears invalid, corrupt, or failed to load.',
    connectionRefused:'The target refused the connection.',
    timeout:'The operation timed out because the target or network did not respond in time.',
    updateActivity:'SteamCMD or the container is checking, downloading, or installing an update.',
    playerJoined:'A player join or login event was detected.',
    playerLeft:'A player leave or disconnect event was detected.',
    deprecated:'A deprecated feature is in use.',
    tunnelIoTimeout:'The tunnel provider timed out while opening a new data connection; the proxy can remain configured while this transfer failed.',
    tunnelConnectionFailed:'A tunnel provider node, control connection, or local service connection failed.',
    serverCrash:'A crash, fatal error, or unhandled exception was detected.',
    genericError:'An error keyword was found; inspect surrounding lines for the cause.',
    genericWarning:'A warning keyword was found; impact depends on context.'
  }
};
const LOG_ACTIONS = {
  zh: {
    none:'', checkBackup:'检查 data/backups 空间、权限和最近归档。',
    freeDisk:'立即释放磁盘空间，然后保存世界并补做备份。',
    checkMemory:'查看仪表盘内存与 OOM 状态；必要时降低负载或提高容器内存限制。',
    checkPorts:'核对 8211/25575/8212 是否被占用，以及 Compose 映射是否一致。',
    checkPermissions:'核对 data 目录所有者、PUID/PGID 和 Windows 文件权限。',
    protectSave:'先复制 data/Pal/Saved/SaveGames，再评估最近可用备份。',
    checkDependency:'确认目标服务正在运行且地址、协议和端口一致。',
    checkNetwork:'检查本机网络、DNS、Docker 与隧道节点；观察错误是否持续出现。',
    reviewSetting:'在官方文档中确认替代接口或设置。',
    checkTunnelNode:'先点击“验证隧道”确认本地 UDP 与控制连接；若仍重复超时，切换 Provider 节点或网络后再测试。',
    checkCrash:'保护存档并查看异常前 30–50 行，重点检查 OOM、Mod、更新和存档错误。',
    inspectContext:'查看该行前后 20 行；若持续重复，再按具体模块处理。'
  },
  en: {
    none:'', checkBackup:'Check backup storage, permissions, and the latest archive.',
    freeDisk:'Free disk space immediately, then save and create a backup.',
    checkMemory:'Review memory and OOM state; reduce load or raise the container limit.',
    checkPorts:'Check port ownership and Compose mappings.',
    checkPermissions:'Check data directory ownership, PUID/PGID, and Windows permissions.',
    protectSave:'Copy SaveGames before attempting recovery.',
    checkDependency:'Confirm the target service, address, protocol, and port.',
    checkNetwork:'Check local networking, Docker, DNS, and the tunnel node.',
    reviewSetting:'Review the official replacement for this deprecated feature.',
    checkTunnelNode:'Verify local UDP and the control connection; if timeouts repeat, change the provider node or network.',
    checkCrash:'Protect the save and inspect 30–50 lines before the crash.',
    inspectContext:'Inspect roughly 20 surrounding lines before acting.'
  }
};

function logExplanation(entry) {
  return LOG_EXPLANATIONS[currentLang][entry.code] || LOG_EXPLANATIONS[currentLang].activity;
}
function configuredPortAction() {
  const game = String(envValues.PORT || 8211);
  const query = String(envValues.QUERY_PORT || 27015);
  const rest = String(envValues.REST_API_PORT || 8212);
  const rcon = String(envValues.RCON_PORT || 25575);
  const restRaw = envValues.REST_API_ENABLED;
  const legacyRaw = envValues.ENABLE_LEGACY_RCON;
  const rconRaw = envValues.RCON_ENABLED;
  const restEnabled = restRaw === undefined || restRaw === null || restRaw === ''
    ? true : /^(true|1|yes)$/i.test(String(restRaw));
  const rconEnabled = (rconRaw !== undefined && rconRaw !== null && /^(true|1|yes)$/i.test(String(rconRaw))) ||
    (legacyRaw !== undefined && legacyRaw !== null && /^(true|1|yes)$/i.test(String(legacyRaw)));
  if (currentLang === 'zh') {
    return `核对游戏 UDP ${game}、查询 UDP ${query}、REST TCP ${rest}${restEnabled ? '' : '（已关闭）'}${rconEnabled ? `、RCON TCP ${rcon}` : '；RCON 当前关闭'}，以及 Compose 映射是否一致。`;
  }
  return `Check game UDP ${game}, query UDP ${query}, REST TCP ${rest}${restEnabled ? '' : ' (disabled)'}${rconEnabled ? `, and RCON TCP ${rcon}` : '; RCON is disabled'}, plus Compose mappings.`;
}
function logAction(entry) {
  if (entry.actionCode === 'checkPorts') return configuredPortAction();
  return LOG_ACTIONS[currentLang][entry.actionCode] || '';
}

async function loadLogs() {
  try {
    const smart = $('smartLogs').checked;
    const [r, incidents, archives] = await Promise.all([
      api(smart ? '/api/logs/insights?lines=300' : '/api/logs?lines=300'),
      api('/api/incidents?limit=80'),
      api('/api/log-archives')
    ]);
    const body = $('logBody');
    if (r.ok) {
      if (smart) {
        body.innerHTML = formatInsightLogs(r.entries || []);
        renderLogSummary(r.summary || {});
      } else {
        body.innerHTML = formatLogs(r.logs);
        renderLogSummary({});
      }
      renderIncidents(incidents.incidents || []);
      renderLogArchives(archives);
      if ($('autoScroll').checked) body.scrollTop = body.scrollHeight;
    } else {
      body.textContent = t('common.error') + ': ' + r.error;
    }
  } catch (e) { $('logBody').textContent = t('common.error') + ': ' + e.message; }
}

function renderLogArchives(data) {
  const list = $('logArchiveList');
  const archives = Array.isArray(data?.archives) ? data.archives : [];
  const zh = currentLang === 'zh';
  $('archivePanelNote').textContent = data?.collectorRunning
    ? (zh
      ? `自动归档运行中 · 北京时间 00:00–24:00 · ${archives.length} 个文件 · 永久保留`
      : `Collector running · 00:00–24:00 Asia/Shanghai · ${archives.length} files · no automatic deletion`)
    : (zh
      ? `自动归档未运行；可立即刷新。北京时间 00:00–24:00，历史文件永久保留。`
      : `Collector is not running; refresh manually. Asia/Shanghai daily files are retained.`);
  if (!archives.length) {
    list.innerHTML = `<div class="empty-state">${zh ? '尚无每日日志归档' : 'No daily log archives yet'}</div>`;
    return;
  }
  list.innerHTML = archives.map(item => `<div class="archive-item">
    <div>
      <div class="archive-date">${escapeHtml(item.date || item.name)}</div>
      <div class="archive-meta">${escapeHtml(String(item.sizeKb || 0))} KB · ${escapeHtml(new Date(item.updatedAt).toLocaleString())}</div>
    </div>
    <a class="archive-download" href="/api/log-archives/download?name=${encodeURIComponent(item.name)}">${zh ? '下载 TXT' : 'Download TXT'}</a>
  </div>`).join('');
}

async function refreshLogArchives() {
  const button = $('btnRefreshArchives');
  button.disabled = true;
  button.textContent = currentLang === 'zh' ? '正在归档…' : 'Archiving…';
  try {
    const result = await api('/api/log-archives/refresh', {method: 'POST'});
    renderLogArchives(result);
    toast(currentLang === 'zh' ? '今天的日志归档已刷新' : 'Today’s archive was refreshed', 'success',
      currentLang === 'zh' ? '日志归档' : 'Log archive');
  } catch (error) {
    toast(error.message, 'error', currentLang === 'zh' ? '归档失败' : 'Archive failed');
  } finally {
    button.disabled = false;
    button.textContent = currentLang === 'zh' ? '立即归档今天' : 'Archive today';
  }
}

function formatInsightLogs(entries) {
  if (!entries.length) return `<span style="color: var(--text-faint);">${t('common.noLogs')}</span>`;
  return entries.map(entry => {
    const action = logAction(entry);
    return `<div class="insight-entry ${escapeHtml(entry.severity || 'info')}">
      <div class="insight-raw">${escapeHtml(entry.raw || '')}</div>
      <div class="insight-translation">${escapeHtml(t('logs.explanation'))}: ${escapeHtml(logExplanation(entry))}</div>
      ${action ? `<div class="insight-action">${escapeHtml(t('logs.suggestion'))}: ${escapeHtml(action)}</div>` : ''}
    </div>`;
  }).join('');
}

function renderLogSummary(summary) {
  $('logCriticalCount').textContent = Number(summary.critical || 0);
  $('logErrorCount').textContent = Number(summary.error || 0);
  $('logWarningCount').textContent = Number(summary.warning || 0);
  $('logRecordedCount').textContent = Number(summary.recorded || 0);
}

function renderIncidents(items) {
  const list = $('incidentList');
  if (!items.length) {
    list.innerHTML = `<div class="empty-state">${currentLang === 'zh' ? '尚未记录错误或严重异常' : 'No error incidents recorded'}</div>`;
    return;
  }
  list.innerHTML = items.map(item => {
    const explanation = logExplanation(item);
    const when = item.loggedAt || item.observedAt;
    return `<div class="incident-item">
      <div class="incident-item-head">
        <span class="incident-severity">${escapeHtml(item.severity || 'error')}</span>
        <span class="incident-time">${escapeHtml(when ? new Date(when).toLocaleString() : '—')}</span>
      </div>
      <div class="incident-copy">${escapeHtml(explanation)}</div>
    </div>`;
  }).join('');
}

async function loadMiniLog() {
  try {
    const r = await api('/api/logs?lines=50');
    if (r.ok) {
      $('miniLog').innerHTML = formatLogs(r.logs);
    }
  } catch (e) { }
}

function formatLogs(text) {
  if (!text) return `<span style="color: var(--text-faint);">${t('common.noLogs')}</span>`;
  return text.split('\n').map(line => {
    if (!line) return '';
    let cls = 'out';
    if (/error|exception|fatal/i.test(line)) cls = 'lvl-err';
    else if (/warn/i.test(line)) cls = 'lvl-warn';
    else if (/info|log/i.test(line)) cls = 'lvl-info';
    const safe = line.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    return `<span class="log-line"><span class="${cls}">${safe}</span></span>`;
  }).join('\n');
}

$('btnRefreshLogsFull').addEventListener('click', loadLogs);
$('btnRefreshArchives').addEventListener('click', refreshLogArchives);
$('smartLogs').addEventListener('change', loadLogs);
$('autoRefresh').addEventListener('change', (e) => {
  if (e.target.checked) {
    logAutoRefreshTimer = setInterval(loadLogs, 5000);
  } else if (logAutoRefreshTimer) {
    clearInterval(logAutoRefreshTimer);
    logAutoRefreshTimer = null;
  }
});

// ===== RCON =====
function fillRconCommand(command) {
  const input = $('rconInput');
  input.value = command;
  input.focus();
}

function renderRconCmds() {
  const list = $('rconCmdList');
  const riskLabel = {
    safe: currentLang === 'zh' ? '安全' : 'safe',
    player: currentLang === 'zh' ? '玩家操作' : 'player',
    danger: currentLang === 'zh' ? '高风险' : 'danger'
  };
  list.innerHTML = RCON_CMDS.map(c => `<button type="button" class="rcon-cmd-item" data-cmd="${escapeHtml(c.cmd)}">
    <div class="rcon-cmd-meta">
      <span>${escapeHtml(c.cmd)}</span>
      <span class="rcon-risk ${escapeHtml(c.risk)}">${escapeHtml(riskLabel[c.risk])}</span>
    </div>
    <span class="desc">${escapeHtml(t('rconcmd.' + c.key))}</span>
  </button>`).join('');
  list.querySelectorAll('.rcon-cmd-item').forEach(el => {
    el.addEventListener('click', () => {
      fillRconCommand(el.dataset.cmd);
    });
  });
}
renderRconCmds();

async function runRestManagement(operation, payload, confirmation) {
  if (confirmation) {
    const confirmed = await showModal(t(confirmation.title), t(confirmation.body));
    if (!confirmed) return;
  }
  const status = $('restManagementStatus');
  if (status) status.textContent = currentLang === 'zh' ? '正在请求 REST…' : 'Sending REST request…';
  try {
    const result = await api('/api/management', {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({ operation, ...payload })
    });
    if (status) status.textContent = result.ok
      ? (currentLang === 'zh' ? `REST 操作已完成：${operation}` : `REST operation completed: ${operation}`)
      : (result.error || t('common.error'));
    if (result.ok) { toast(currentLang === 'zh' ? 'REST 操作已完成' : 'REST operation completed', 'success'); await loadDashboard(); }
  } catch (error) {
    if (status) status.textContent = error.message;
    toast(error.message, 'error', t('common.networkError'));
  }
}

$('btnRestAnnounce').addEventListener('click', () => {
  const message = $('restAnnouncement').value.trim();
  if (!message) { $('restAnnouncement').focus(); return; }
  runRestManagement('announce', { message });
});
$('btnRestPlayerAction').addEventListener('click', () => {
  const userid = $('restPlayerId').value.trim();
  const operation = $('restPlayerAction').value;
  const message = $('restPlayerMessage').value.trim();
  if (!userid) { $('restPlayerId').focus(); return; }
  runRestManagement(operation, { userid, message }, { title: 'modal.rcon.player.title', body: 'modal.rcon.player.body' });
});
$('btnRestShutdown').addEventListener('click', () => {
  const waittime = Math.max(0, Math.min(600, Number($('restShutdownWait').value || 30)));
  runRestManagement('shutdown', { waittime, message: currentLang === 'zh' ? '服务器将按本地控制台请求停服。' : 'Server shutdown requested by the local console.' }, { title: 'modal.rcon.runtime.title', body: 'modal.rcon.runtime.body' });
});

function rconConfirmationFor(command) {
  const verb = String(command || '').trim().split(/\s+/, 1)[0].toLowerCase();
  if (['kickplayer', 'banplayer', 'unbanplayer'].includes(verb)) {
    return { title: 'modal.rcon.player.title', body: 'modal.rcon.player.body' };
  }
  if (['shutdown', 'doexit'].includes(verb)) {
    return { title: 'modal.rcon.runtime.title', body: 'modal.rcon.runtime.body' };
  }
  return null;
}

async function sendRcon() {
  const cmd = $('rconInput').value.trim();
  if (!cmd) return;
  const confirmation = rconConfirmationFor(cmd);
  if (confirmation) {
    const confirmed = await showModal(t(confirmation.title), t(confirmation.body));
    if (!confirmed) return;
  }
  const output = $('rconOutput');
  output.innerHTML += `<div class="rcon-line cmd">${escapeHtml(cmd)}</div>`;
  output.scrollTop = output.scrollHeight;
  $('rconInput').value = '';
  try {
    const r = await api('/api/rcon', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({cmd}) });
    if (r.ok) {
      output.innerHTML += `<div class="rcon-line out">${escapeHtml(r.output || t('rcon.empty'))}</div>`;
    } else {
      output.innerHTML += `<div class="rcon-line err">${escapeHtml(r.error || t('common.error'))}</div>`;
    }
  } catch (e) {
    output.innerHTML += `<div class="rcon-line err">${escapeHtml(e.message)}</div>`;
  }
  output.scrollTop = output.scrollHeight;
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

$('btnRconSend').addEventListener('click', sendRcon);
$('rconInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') sendRcon(); });
$('btnRconGuidePlayers').addEventListener('click', focusPlayerTable);
$('btnRconGuideInfo').addEventListener('click', () => fillRconCommand('info'));
$('btnRconPrepareBroadcast').addEventListener('click', () => {
  const message = $('rconBroadcastMessage').value.trim();
  if (!message) {
    $('rconBroadcastMessage').focus();
    toast(t('rcon.broadcast.empty'), 'warn', t('rcon.error'));
    return;
  }
  fillRconCommand(`broadcast ${message}`);
  toast(t('rcon.broadcast.ready'), 'success');
});

// ===== Settings =====
async function loadEnv() {
  try {
    const payload = await api('/api/settings');
    FIELDS = Array.isArray(payload.schema) ? payload.schema : [];
    envValues = payload.values || {};
    explicitSettings = new Set(payload.explicit || []);
    configuredSecrets = new Set(payload.configuredSecrets || []);
    settingsExclusions = payload.exclusions || [];
    $('metaPort').textContent = `${envValues.PORT || 8211}/UDP`;
    envDraft = {};
    envModified.clear();
    populateGroupFilter();
    renderSettings();
    refreshUpdateStatusFallback().catch(() => {});
  } catch (e) {
    $('settingsGrid').innerHTML = `<div style="color: var(--danger);">${escapeHtml(t('common.error'))}: ${escapeHtml(e.message)}</div>`;
  }
}

function groupLabel(group) {
  return GROUP_LABELS[currentLang]?.[group] || GROUP_LABELS.en[group] || group;
}

const FIELD_PRIORITY = {
  SERVER_NAME:1, SERVER_DESCRIPTION:2, PLAYERS:3, COOP_PLAYER_MAX_NUM:4,
  SERVER_PASSWORD:5, ADMIN_PASSWORD:6, PORT:1, PUBLIC_IP:2, PUBLIC_PORT:3,
  COMMUNITY:4, CROSSPLAY_PLATFORMS:5, REST_API_ENABLED:10, REST_API_PORT:11,
  RCON_ENABLED:20, RCON_PORT:21, BACKUP_ENABLED:1, BACKUP_CRON_EXPRESSION:2,
  DELETE_OLD_BACKUPS:3, OLD_BACKUP_DAYS:4, UPDATE_ON_BOOT:10,
  AUTO_UPDATE_ENABLED:11, AUTO_REBOOT_ENABLED:20, AUTO_PAUSE_ENABLED:30,
  DISABLE_GENERATE_ENGINE:1
};

function compareFields(a, b) {
  const priority = (FIELD_PRIORITY[a.key] ?? 1000) - (FIELD_PRIORITY[b.key] ?? 1000);
  return priority || settingLabel(a).localeCompare(settingLabel(b), currentLang === 'zh' ? 'zh-CN' : 'en');
}

function populateGroupFilter() {
  const current = $('groupFilter').value;
  const groups = GROUP_ORDER.filter(group => FIELDS.some(field => field.group === group));
  $('groupFilter').innerHTML = [
    `<option value="">${escapeHtml(GROUP_LABELS[currentLang].all)}</option>`,
    ...groups.map(group => `<option value="${group}">${escapeHtml(groupLabel(group))}</option>`)
  ].join('');
  if (groups.includes(current)) $('groupFilter').value = current;
}

function effectiveSettingValue(key) {
  if (Object.prototype.hasOwnProperty.call(envDraft, key)) return envDraft[key];
  if (Object.prototype.hasOwnProperty.call(envValues, key)) return envValues[key];
  const field = FIELDS.find(item => item.key === key);
  return field?.default ?? '';
}

function dependencyEnabled(field) {
  const rule = field.dependsOn;
  if (!rule) return true;
  if (rule.endsWith('=configured')) {
    const key = rule.slice(0, -'=configured'.length);
    return configuredSecrets.has(key) || Boolean(effectiveSettingValue(key));
  }
  if (rule.includes('!=')) {
    const [key, expected] = rule.split('!=');
    return String(effectiveSettingValue(key)).toLowerCase() !== expected.toLowerCase();
  }
  const [key, expected] = rule.split('=');
  return String(effectiveSettingValue(key)).toLowerCase() === String(expected).toLowerCase();
}

const SETTING_DOCS = {
  officialConfig: {
    url: 'https://docs.palworldgame.com/settings-and-operation/configuration/',
    zh: 'Palworld 官方配置说明',
    en: 'Official Palworld configuration'
  },
  officialPvp: {
    url: 'https://docs.palworldgame.com/settings-and-operation/pvp/',
    zh: 'Palworld 官方 PvP 说明',
    en: 'Official Palworld PvP guide'
  },
  officialArguments: {
    url: 'https://docs.palworldgame.com/settings-and-operation/arguments/',
    zh: 'Palworld 官方启动参数',
    en: 'Official Palworld startup arguments'
  },
  imageGame: {
    url: 'https://palworld-server-docker.loef.dev/getting-started/configuration/game-settings',
    zh: '社区镜像游戏设置映射',
    en: 'Community image game settings'
  },
  imageServer: {
    url: 'https://palworld-server-docker.loef.dev/getting-started/configuration/server-settings',
    zh: '社区镜像服务器设置',
    en: 'Community image server settings'
  },
  imageEngine: {
    url: 'https://palworld-server-docker.loef.dev/getting-started/configuration/engine-settings',
    zh: '社区镜像 Engine.ini 设置',
    en: 'Community image Engine.ini settings'
  }
};

const EXACT_SETTING_MEANING_ZH = {
  SERVER_NAME:'玩家在服务器列表和连接信息中看到的服务器名称。',
  SERVER_DESCRIPTION:'服务器列表或查询接口中显示的说明文字。',
  PLAYERS:'允许同时连接服务器的玩家总上限；本项目当前计划值为 8。',
  COOP_PLAYER_MAX_NUM:'合作队伍可容纳的玩家上限，不能高于服务器玩家总上限。',
  SERVER_PASSWORD:'玩家加入服务器时需要输入的密码；留空表示不设加入密码。',
  ADMIN_PASSWORD:'REST、RCON 和游戏内管理员认证使用的高权限密码。',
  DIFFICULTY:'选择服务端难度预设；单独设置的倍率仍会形成自定义规则。',
  RANDOMIZER_TYPE:'控制野生帕鲁随机化范围：不随机、区域内随机或全地图随机。',
  RANDOMIZER_SEED:'随机化所用种子；相同种子与相同规则用于复现同一分布。',
  IS_RANDOMIZER_PAL_LEVEL_RANDOM:'随机化开启时，是否同时随机帕鲁等级。',
  DAYTIME_SPEEDRATE:'控制白天时间流逝速度，不是白天持续分钟数。',
  NIGHTTIME_SPEEDRATE:'控制夜晚时间流逝速度，不是夜晚持续分钟数。',
  EXP_RATE:'控制玩家与帕鲁获得经验的倍率。',
  PAL_CAPTURE_RATE:'控制捕捉成功率的倍率。',
  PAL_SPAWN_NUM_RATE:'控制野外帕鲁生成数量倍率；生成更多会增加服务器负载。',
  ENABLE_INVADER_ENEMY:'控制据点入侵事件是否会发生。',
  PAL_EGG_DEFAULT_HATCHING_TIME:'设置巨大蛋的基础孵化小时数，其他蛋按比例计算。',
  WORK_SPEED_RATE:'控制玩家与帕鲁工作速度倍率。',
  AUTO_SAVE_SPAN:'游戏世界自动保存的时间间隔，单位为秒。',
  ENABLE_FAST_TRAVEL:'控制玩家能否使用快速传送。',
  IS_START_LOCATION_SELECT_BY_MAP:'控制新角色是否可以从地图选择出生点。',
  SUPPLY_DROP_SPAN:'控制补给空投的间隔，单位为分钟。',
  ENABLE_PREDATOR_BOSS_PAL:'控制掠食者 Boss 帕鲁是否生成。',
  PAL_DAMAGE_RATE_ATTACK:'控制帕鲁造成伤害的倍率。',
  PAL_DAMAGE_RATE_DEFENSE:'控制帕鲁承受伤害的倍率。',
  PLAYER_DAMAGE_RATE_ATTACK:'控制玩家造成伤害的倍率。',
  PLAYER_DAMAGE_RATE_DEFENSE:'控制玩家承受伤害的倍率。',
  DEATH_PENALTY:'控制普通模式下玩家死亡后丢失哪些内容。',
  ENABLE_PLAYER_TO_PLAYER_DAMAGE:'控制玩家攻击能否对其他玩家造成伤害。',
  ENABLE_FRIENDLY_FIRE:'控制同阵营或友方单位是否会受到友军伤害。',
  ACTIVE_UNKO:'控制玩家是否可以使其他玩家进入击倒而非立即死亡状态。',
  IS_PVP:'启用 PvP 总开关；完整 PvP 还需要同时开启玩家伤害和跨公会防御。',
  HARDCORE:'启用硬核模式相关规则。',
  CHARACTER_RECREATE_IN_HARDCORE:'硬核模式死亡后是否要求重建角色。',
  BLOCK_RESPAWN_TIME:'控制死亡后禁止立即重生的基础时长。',
  RESPAWN_PENALTY_DURATION_THRESHOLD:'决定从何种死亡持续条件开始追加重生惩罚。',
  RESPAWN_PENALTY_TIME_SCALE:'控制重生惩罚时间的倍率。',
  ALLOW_ENHANCE_STAT_ATTACK:'控制升级加点时能否强化攻击属性。',
  PLAYER_STOMACH_DECREASE_RATE:'控制玩家饱食度下降倍率。',
  PLAYER_STAMINA_DECREASE_RATE:'控制玩家耐力消耗倍率。',
  PLAYER_AUTO_HP_REGEN_RATE:'控制玩家自然生命恢复倍率。',
  PLAYER_AUTO_HP_REGEN_RATE_IN_SLEEP:'控制玩家睡眠时生命恢复倍率。',
  ENABLE_AIM_ASSIST_PAD:'控制手柄瞄准辅助。',
  ENABLE_AIM_ASSIST_KEYBOARD:'控制键鼠瞄准辅助。',
  PLAYER_DATA_PAL_STORAGE_UPDATE_CHECK_TICK_INTERVAL:'控制检查玩家帕鲁存储数据更新的 Tick 间隔。',
  ALLOW_ENHANCE_STAT_HEALTH:'控制升级加点时能否强化生命属性。',
  ALLOW_ENHANCE_STAT_STAMINA:'控制升级加点时能否强化耐力属性。',
  ALLOW_ENHANCE_STAT_WORK_SPEED:'控制升级加点时能否强化工作速度。',
  PAL_STOMACH_DECREASE_RATE:'控制帕鲁饱食度下降倍率。',
  PAL_STAMINA_DECREASE_RATE:'控制帕鲁耐力消耗倍率。',
  PAL_AUTO_HP_REGEN_RATE:'控制帕鲁自然生命恢复倍率。',
  PAL_AUTO_HP_REGEN_RATE_IN_SLEEP:'控制帕鲁在帕鲁终端休息时的生命恢复倍率。',
  PAL_LOST:'硬核规则下死亡时是否永久失去携带的帕鲁。',
  MONSTER_FARM_ACTION_SPEED_RATE:'控制牧场帕鲁执行产出动作的速度倍率。',
  COLLECTION_DROP_RATE:'控制采集物产出数量倍率。',
  COLLECTION_OBJECT_HP_RATE:'控制矿石、树木等采集对象的生命值倍率。',
  COLLECTION_OBJECT_RESPAWN_SPEED_RATE:'控制采集对象重新生成速度倍率。',
  ENEMY_DROP_ITEM_RATE:'控制敌人掉落物数量倍率。',
  DROP_ITEM_MAX_NUM:'全地图普通地面掉落物的数量上限。',
  DROP_ITEM_MAX_NUM_UNKO:'全地图击倒相关掉落对象的数量上限。',
  DROP_ITEM_ALIVE_MAX_HOURS:'地面掉落物最多保留的小时数。',
  ITEM_WEIGHT_RATE:'控制物品重量倍率。',
  EQUIPMENT_DURABILITY_DAMAGE_RATE:'控制装备耐久损耗倍率。',
  ITEM_CONTAINER_FORCE_MARK_DIRTY_INTERVAL:'容器界面打开时强制重同步库存的秒数间隔。',
  ITEM_CORRUPTION_MULTIPLIER:'控制食物等可腐坏物品的腐坏速度倍率。',
  PHYSICS_ACTIVE_DROP_ITEM_MAX_NUM:'同时启用物理模拟的掉落物上限；其余掉落物仍可存在。',
  DISPLAY_PVP_ITEM_NUM_ON_WORLD_MAP_PLAYER:'PvP 时在地图显示玩家掉落物数量。',
  ADDITIONAL_DROP_ITEM_WHEN_PLAYER_KILLING_IN_PVP_MODE:'PvP 击杀玩家时追加的物品标识。',
  ADDITIONAL_DROP_ITEM_NUM_WHEN_PLAYER_KILLING_IN_PVP_MODE:'PvP 击杀玩家时追加物品的数量。',
  ADDITIONAL_DROP_ITEM_WHEN_PLAYER_KILLING_IN_PVP_MODE_ENABLED:'是否启用 PvP 击杀玩家追加掉落。',
  ALLOW_ENHANCE_STAT_WEIGHT:'控制升级加点时能否强化负重。',
  BUILD_OBJECT_HP_RATE:'控制建筑生命值倍率。',
  BUILD_OBJECT_DAMAGE_RATE:'控制建筑受到伤害的倍率。',
  BUILD_OBJECT_DETERIORATION_DAMAGE_RATE:'控制据点范围外建筑的自然腐坏伤害倍率。',
  BASE_CAMP_MAX_NUM:'全服务器可存在的据点总数。',
  BASE_CAMP_WORKER_MAX_NUM:'每个据点可分配的工作帕鲁上限；提高会增加负载。',
  BASE_CAMP_MAX_NUM_IN_GUILD:'每个公会可拥有的据点上限，官方当前上限为 10。',
  BUILD_AREA_LIMIT:'控制据点建筑区域的范围倍率。',
  MAX_BUILDING_LIMIT_NUM:'每名玩家可建造对象的上限；0 表示不限制。',
  DISPLAY_PVP_ITEM_NUM_ON_WORLD_MAP_BASE_CAMP:'PvP 时在地图显示据点相关掉落物数量。',
  ENABLE_BUILDING_PLAYER_UID_DISPLAY:'建筑信息中是否显示建造者玩家 UID。',
  BUILDING_NAME_DISPLAY_CACHE_TTL_SECONDS:'建筑名称显示缓存的有效时间，单位为秒。',
  AUTO_RESET_GUILD_NO_ONLINE_PLAYERS:'公会长期无人在线时是否自动重置。',
  AUTO_RESET_GUILD_TIME_NO_ONLINE_PLAYERS:'公会无人在线达到多少小时后自动重置。',
  GUILD_PLAYER_MAX_NUM:'单个公会允许的玩家人数上限。',
  IS_MULTIPLAY:'控制服务器多人游戏规则是否启用。',
  CAN_PICKUP_OTHER_GUILD_DEATH_PENALTY_DROP:'是否允许拾取其他公会玩家的死亡掉落。',
  EXIST_PLAYER_AFTER_LOGOUT:'玩家下线后其角色是否继续留在世界中。',
  ENABLE_DEFENSE_OTHER_GUILD_PLAYER:'控制是否允许攻击或防御其他公会玩家；也是完整 PvP 的必要开关。',
  INVISIBLE_OTHER_GUILD_BASE_CAMP_AREA_FX:'是否隐藏其他公会据点区域的视觉效果。',
  GUILD_REJOIN_COOLDOWN_MINUTES:'退出公会后再次加入公会的冷却时间，单位为分钟。',
  AUTO_TRANSFER_MASTER_CHECK_INTERVAL_SECONDS:'自动转移会长时检查离线状态的秒数间隔。',
  AUTO_TRANSFER_MASTER_THRESHOLD_DAYS:'会长离线达到多少天后允许自动转移。',
  MAX_GUILDS_PER_FRAME:'每帧最多处理的公会数量，用于限制瞬时服务器负载。',
  SHOW_PLAYER_LIST:'控制游戏内是否向玩家显示玩家列表。',
  CHAT_POST_LIMIT_PER_MINUTE:'每名玩家每分钟允许发送的聊天消息数。',
  ALLOW_GLOBAL_PALBOX_EXPORT:'允许从全局帕鲁终端导出帕鲁。',
  ALLOW_GLOBAL_PALBOX_IMPORT:'允许向全局帕鲁终端导入帕鲁，可能影响跨世界平衡。',
  ALLOW_CLIENT_MOD:'只允许客户端使用 Mod；不会安装服务端 Mod，也不会启用本项目的 Mod 管理器。',
  IS_SHOW_JOIN_LEFT_MESSAGE:'控制游戏内是否广播玩家加入和离开消息。',
  DENY_TECHNOLOGY_LIST:'阻止玩家解锁指定科技的列表。',
  ENABLE_VOICE_CHAT:'控制游戏内语音聊天。',
  VOICE_CHAT_MAX_VOLUME_DISTANCE:'语音保持最大音量的距离阈值。',
  VOICE_CHAT_ZERO_VOLUME_DISTANCE:'语音衰减到完全听不见的距离阈值。',
  PUBLIC_PORT:'社区服务器列表公布的端口；不会改变真实监听端口。',
  PUBLIC_IP:'社区服务器列表公布的公网 IP；私服经隧道连接通常不依赖此值。',
  RCON_ENABLED:'启用旧版 RCON 管理接口；官方已标记为 deprecated，项目只绑定本机。',
  RCON_PORT:'RCON 的 TCP 监听端口，仅用于本机兼容管理。',
  REGION:'社区列表显示的服务器区域文本。',
  USEAUTH:'控制社区服务器是否使用平台认证流程。',
  BAN_LIST_URL:'启动时获取封禁名单的 HTTP(S) 地址。',
  REST_API_ENABLED:'启用官方 REST API；仪表盘、玩家详情和首选管理操作依赖它。',
  REST_API_PORT:'官方 REST API 的 TCP 监听端口，项目只映射到本机。',
  SERVER_REPLICATE_PAWN_CULL_DISTANCE:'服务器向客户端同步帕鲁实体的距离，官方建议 5000–15000。',
  CROSSPLAY_PLATFORMS:'允许连接的平台列表，格式如 (Steam,Xbox,PS5,Mac)。',
  PORT:'游戏 UDP 监听端口；修改后还要同步 Windows 防火墙和已配置 Provider 的本地目标。',
  QUERY_PORT:'Steam 查询协议端口；不用于玩家的实际游戏连接。',
  COMMUNITY:'是否把服务器注册到公共社区服务器列表。',
  USE_BACKUP_SAVE_DATA:'启用 Palworld 自身的存档备份机制；频繁备份会增加磁盘负载。',
  UPDATE_ON_BOOT:'容器每次启动时是否先检查并安装游戏更新。',
  BACKUP_ENABLED:'启用社区镜像的定时存档归档。',
  BACKUP_CRON_EXPRESSION:'定时备份的五段 cron 表达式，按容器时区执行。',
  DELETE_OLD_BACKUPS:'是否自动删除超过保留期的旧备份。',
  OLD_BACKUP_DAYS:'备份归档保留天数。',
  AUTO_UPDATE_ENABLED:'启用社区镜像的定时游戏更新。',
  AUTO_UPDATE_CRON_EXPRESSION:'定时更新检查的五段 cron 表达式。',
  AUTO_UPDATE_WARN_MINUTES:'自动更新前向在线玩家发出警告的提前分钟数。',
  AUTO_REBOOT_ENABLED:'启用按 cron 计划重启服务端。',
  AUTO_REBOOT_EVEN_IF_PLAYERS_ONLINE:'即使有玩家在线也执行计划重启。',
  AUTO_REBOOT_WARN_MINUTES:'计划重启前的广播警告分钟数。',
  AUTO_REBOOT_CRON_EXPRESSION:'计划重启的五段 cron 表达式。',
  AUTO_PAUSE_ENABLED:'无人在线一段时间后自动暂停游戏进程以节省资源。',
  AUTO_PAUSE_TIMEOUT_EST:'估算无人在线多久后暂停，单位为秒。',
  AUTO_PAUSE_LOG:'是否记录自动暂停状态变化。',
  AUTO_PAUSE_DEBUG:'是否输出自动暂停检测的调试日志。',
  LOG_FORMAT_TYPE:'Palworld 游戏日志格式，只接受 Text 或 Json；不改变网页显示样式。',
  ENABLE_PLAYER_LOGGING:'社区镜像是否定期记录玩家加入与离开。',
  PLAYER_LOGGING_POLL_PERIOD:'社区镜像轮询在线玩家列表的间隔秒数。',
  LOG_FILTER_ENABLED:'是否由社区镜像过滤低于指定级别的日志。',
  LOG_LEVEL:'社区镜像保留日志的最低严重级别。',
  DISCORD_WEBHOOK_URL:'Discord 通知的默认 Webhook，只写且不会回显。',
  DISCORD_CONNECT_TIMEOUT:'向 Discord 建立连接的超时时间，单位为秒。',
  DISCORD_MAX_TIMEOUT:'单次 Discord 通知允许的最长总时间，单位为秒。',
  DISCORD_SUPPRESS_NOTIFICATIONS:'发送 Discord 消息时是否抑制 @ 通知效果。',
  TZ:'容器时区；cron 备份、更新和重启都按此时区解释。',
  PUID:'容器内运行用户的 UID，决定 data 文件所有者。',
  PGID:'容器内运行用户组的 GID，决定 data 文件所属组。',
  MULTITHREADING:'旧版多线程启动开关，社区镜像已不推荐使用。',
  ENABLE_PERF_THREADING_ARGS:'启用官方性能线程启动参数组合。',
  WORKER_THREADS_SERVER:'传给服务端的工作线程数量。',
  PALWORLD_ALLOW_NEGATIVE_DELTA_TIME:'允许负 Delta Time 的兼容性恢复开关，仅用于特定崩溃问题。',
  ENABLE_GAMEDATA_API:'启用社区镜像附带的游戏数据 API 功能。',
  USE_DEPOT_DOWNLOADER:'改用 DepotDownloader 获取服务端文件。',
  INSTALL_BETA_INSIDER:'安装测试分支版本；可能与正式版客户端不兼容。',
  DISABLE_GENERATE_ENGINE:'开启时不生成 Engine.ini；关闭后本组引擎设置才会生效。',
  LAN_SERVER_MAX_TICK_RATE:'局域网服务端最大 Tick 率。',
  NET_SERVER_MAX_TICK_RATE:'互联网服务端最大 Tick 率。',
  CONFIGURED_INTERNET_SPEED:'引擎假定的互联网带宽，单位为 byte/s。',
  CONFIGURED_LAN_SPEED:'引擎假定的局域网带宽，单位为 byte/s。',
  MAX_CLIENT_RATE:'单客户端网络速率上限，单位为 byte/s。',
  MAX_INTERNET_CLIENT_RATE:'互联网单客户端网络速率上限，单位为 byte/s。',
  SMOOTH_FRAME_RATE:'是否限制并平滑服务端帧率波动。',
  SMOOTH_FRAME_RATE_UPPER_LIMIT:'帧率平滑允许的上限。',
  SMOOTH_FRAME_RATE_LOWER_LIMIT:'帧率平滑允许的下限。',
  USE_FIXED_FRAME_RATE:'是否强制固定服务端帧率。',
  FIXED_FRAME_RATE:'启用固定帧率时使用的帧率值。',
  MIN_DESIRED_FRAME_RATE:'引擎期望维持的最低帧率。',
  NET_CLIENT_TICKS_PER_SECOND:'每秒处理客户端网络 Tick 的上限。',
  ENABLE_NON_LOGIN_PENALTY:'控制非正常登录或离线相关惩罚规则。'
};

function discordSettingMeaning(field) {
  const match = field.key.match(/^DISCORD_(.+)_(MESSAGE_ENABLED|MESSAGE_URL|MESSAGE)$/);
  if (!match) return '';
  const eventNames = {
    PLAYER_JOIN:'玩家加入', PLAYER_LEAVE:'玩家离开', PRE_BACKUP:'备份开始前',
    POST_BACKUP:'备份完成后', PRE_BACKUP_DELETE:'删除旧备份前',
    POST_BACKUP_DELETE:'删除旧备份后', ERR_BACKUP_DELETE:'删除旧备份失败时',
    PRE_SHUTDOWN:'关服前', POST_SHUTDOWN:'关服后', PRE_START:'启动前',
    PRE_UPDATE_BOOT:'启动更新前', POST_UPDATE_BOOT:'启动更新后'
  };
  const event = eventNames[match[1]] || match[1];
  if (match[2] === 'MESSAGE_ENABLED') return `控制是否在${event}发送 Discord 通知。`;
  if (match[2] === 'MESSAGE_URL') return `${event}通知专用的 Webhook；留空时使用默认 Webhook。`;
  return `${event}发送到 Discord 的消息模板，可包含镜像支持的占位符。`;
}

function settingDoc(field) {
  if (/(^|_)PVP|PLAYER_TO_PLAYER_DAMAGE|DEFENSE_OTHER_GUILD/.test(field.key)) return SETTING_DOCS.officialPvp;
  if (field.source === 'engine') return SETTING_DOCS.imageEngine;
  if (field.source === 'container') {
    if (/^(PORT|PLAYERS|MULTITHREADING|ENABLE_PERF|WORKER_THREADS|COMMUNITY)/.test(field.key)) return SETTING_DOCS.officialArguments;
    return SETTING_DOCS.imageServer;
  }
  return SETTING_DOCS.officialConfig;
}

function settingMeaning(field) {
  const zh = currentLang === 'zh';
  if (zh) {
    const exact = EXACT_SETTING_MEANING_ZH[field.key];
    if (exact) return exact;
    const discord = discordSettingMeaning(field);
    if (discord) return discord;
    const label = settingLabel(field);
    if (field.type === 'boolean') return `控制“${label}”功能是否启用。`;
    if (/URL$/.test(field.key)) return `为“${label}”指定 HTTP(S) 地址。`;
    if (/MESSAGE$/.test(field.key)) return `定义“${label}”使用的消息文本或模板。`;
    if (/CRON_EXPRESSION$/.test(field.key)) return `定义“${label}”的五段 cron 计划。`;
    if (field.type === 'integer' || field.type === 'number') return `设置“${label}”使用的数值。`;
    return `设置“${label}”的文本值。`;
  }
  const label = settingLabel(field);
  if (field.type === 'boolean') return `Controls whether ${label} is enabled.`;
  if (field.type === 'integer' || field.type === 'number') return `Sets the numeric value used by ${label}.`;
  return `Sets the value used by ${label}.`;
}

function choiceEffect(field) {
  const zh = currentLang === 'zh';
  const choicesZh = {
    DIFFICULTY:'None=不套用难度预设；Normal=普通预设；Difficult=困难预设。',
    RANDOMIZER_TYPE:'None=关闭；Region=在各区域内随机；All=全地图范围随机。',
    DEATH_PENALTY:'None=不丢失；Item=丢背包物品；ItemAndEquipment=再含装备；All=丢失全部适用内容。',
    LOG_FORMAT_TYPE:'Text=便于人读；Json=便于程序逐字段解析。',
    LOG_LEVEL:'TRACE 最详细，依次为 DEBUG、INFO、WARN、ERROR；级别越高，保留的日志越少。'
  };
  if (zh && choicesZh[field.key]) return choicesZh[field.key];
  const options = (field.options || []).join(' / ');
  return zh ? `可选值：${options}。` : `Allowed values: ${options}.`;
}

function numericEffect(field) {
  const zh = currentLang === 'zh';
  const label = settingLabel(field);
  const key = field.key;
  if (!zh) return `Use a finite number${field.min != null ? ` from ${field.min}` : ''}${field.max != null ? ` to ${field.max}` : ''}.`;
  const exact = {
    DAYTIME_SPEEDRATE:'1 为默认；调大后白天流逝更快、持续更短，调小则持续更久。',
    NIGHTTIME_SPEEDRATE:'1 为默认；调大后夜晚流逝更快、持续更短，调小则持续更久。',
    PAL_EGG_DEFAULT_HATCHING_TIME:'调大需要更久孵化，调小更快；0 表示无需等待。',
    COLLECTION_OBJECT_RESPAWN_SPEED_RATE:'1 为默认；此字段实际表示重生间隔，调小会更快再生，调大等待更久。',
    DROP_ITEM_ALIVE_MAX_HOURS:'调大让掉落物保留更久并占用更多资源；调小会更早清理。',
    PHYSICS_ACTIVE_DROP_ITEM_MAX_NUM:'调大让更多掉落物同时模拟物理并增加负载；-1 使用游戏默认行为。',
    SERVER_REPLICATE_PAWN_CULL_DISTANCE:'调大可在更远距离同步帕鲁，但增加网络与服务器负载；官方建议 5000–15000。',
    VOICE_CHAT_MAX_VOLUME_DISTANCE:'调大后保持最大音量的范围更远。',
    VOICE_CHAT_ZERO_VOLUME_DISTANCE:'调大后语音传播更远；应大于最大音量距离。',
    WORKER_THREADS_SERVER:'调大分配更多工作线程，但超过可用 CPU 线程不一定更快。',
    SMOOTH_FRAME_RATE_UPPER_LIMIT:'调大允许更高帧率，同时可能提高 CPU 占用。',
    SMOOTH_FRAME_RATE_LOWER_LIMIT:'调大提高平滑区间下限；必须小于上限。',
    FIXED_FRAME_RATE:'调大提高固定帧率目标并增加 CPU 压力。',
    MIN_DESIRED_FRAME_RATE:'调大提高目标，但硬件不足时可能加剧负载。',
    NET_CLIENT_TICKS_PER_SECOND:'调大可提高网络更新频率，同时增加 CPU 和带宽占用。',
    ITEM_CONTAINER_FORCE_MARK_DIRTY_INTERVAL:'调大降低重同步频率、减少开销但更新更慢；调小同步更及时。',
    PLAYER_DATA_PAL_STORAGE_UPDATE_CHECK_TICK_INTERVAL:'调大降低检查频率；调小检查更及时但更频繁。',
    MAX_GUILDS_PER_FRAME:'调大每帧处理更多公会、完成更快但瞬时负载更高；调小更平滑。',
    AUTO_TRANSFER_MASTER_CHECK_INTERVAL_SECONDS:'调大检查更少；调小更快发现满足转移条件的会长。',
    BUILDING_NAME_DISPLAY_CACHE_TTL_SECONDS:'调大减少名称刷新开销但更新更慢；调小更及时。',
    PLAYER_LOGGING_POLL_PERIOD:'调大轮询更少但进出记录更迟；调小更及时但调用更频繁。',
    PUID:'这是 Linux 用户标识，不按大小比较；必须与 data 目录文件所有者匹配。',
    PGID:'这是 Linux 用户组标识，不按大小比较；必须与 data 目录文件所属组匹配。',
    CONFIGURED_INTERNET_SPEED:'调大减少引擎带宽限流概率，但不能创造真实带宽；单位为 byte/s。',
    CONFIGURED_LAN_SPEED:'调大允许引擎使用更高局域网带宽；单位为 byte/s。',
    MAX_CLIENT_RATE:'调大提高每客户端速率上限，也可能增加总带宽占用；单位为 byte/s。',
    MAX_INTERNET_CLIENT_RATE:'调大提高互联网客户端速率上限，也可能增加总带宽占用；单位为 byte/s。',
    BLOCK_RESPAWN_TIME:'调大后死亡等待重生更久，调小更快；单位为秒。',
    AUTO_RESET_GUILD_TIME_NO_ONLINE_PLAYERS:'调大需要更久无人在线才重置，调小会更早触发。'
  };
  if (exact[key]) return exact[key];
  if (/PORT$/.test(key)) return '端口号没有“越大越强”的含义；只要未占用且与映射、隧道和防火墙一致即可。';
  if (/CRON/.test(key)) return '这是计划表达式，不按数值大小比较。';
  if (/(TIMEOUT|INTERVAL|SPAN|TTL|POLL_PERIOD|COOLDOWN|THRESHOLD|WARN_MINUTES|DAYS|HOURS)/.test(key)) {
    return '调大表示等待、间隔或保留时间更长；调小会更快或更频繁地触发。';
  }
  if (/(MAX|NUM|LIMIT|PLAYERS|COUNT)/.test(key)) {
    return `调大提高“${label}”容量，通常也会增加内存、CPU、网络或存档负载；调小则收紧上限。`;
  }
  if (/(TICK_RATE|FRAME_RATE|TICKS_PER_SECOND)/.test(key)) {
    return '调大提高更新频率或帧率目标，但会增加 CPU 与网络负载；调小更省资源。';
  }
  if (/(SPEED|RATE|SCALE|MULTIPLIER)/.test(key)) {
    return `1 通常代表默认倍率；调大提高“${label}”倍率，调小降低，0 通常表示停止该项变化。`;
  }
  return `当前支持范围：${field.min ?? '未规定下限'} 至 ${field.max ?? '未规定上限'}；数值只改变“${label}”，不代表越大一定越好。`;
}

function settingEffect(field) {
  const zh = currentLang === 'zh';
  let effect = '';
  if (field.key === 'ADMIN_PASSWORD') effect = zh
    ? '至少 16 个字符；这是只写字段，后端不会回显，修改后管理接口使用新密码。'
    : 'At least 16 characters; write-only and never returned by the backend.';
  else if (field.key === 'DENY_TECHNOLOGY_LIST') effect = zh
    ? '填写官方科技 ID 列表；空值表示不禁用科技，错误 ID 不会自动匹配显示名称。'
    : 'Enter official technology IDs; blank denies none.';
  else if (field.key === 'RANDOMIZER_SEED') effect = zh
    ? '只在随机化类型不是 None 时生效；更换字符串会生成不同分布，长度没有强弱含义。'
    : 'Used only when randomizer type is not None; changing it changes the distribution.';
  else if (field.key === 'TZ') effect = zh
    ? '使用 IANA 时区名，例如 Asia/Shanghai；修改后所有 cron 计划的实际触发时刻会改变。'
    : 'Use an IANA timezone such as Asia/Shanghai; cron schedules follow it.';
  else if (field.type === 'choice') effect = choiceEffect(field);
  else if (field.type === 'boolean') effect = zh
    ? `开启=启用“${settingLabel(field)}”；关闭=停用。`
    : `On enables ${settingLabel(field)}; off disables it.`;
  else if (field.type === 'integer' || field.type === 'number') effect = numericEffect(field);
  else if (field.type === 'secret') effect = zh
    ? '这是只写字段：留空且不修改会保留现值；输入新值才替换，后端不会回显。'
    : 'Write-only: leaving it untouched preserves the current value; entering a value replaces it.';
  else if (/CRON_EXPRESSION$/.test(field.key)) effect = zh
    ? '格式为“分 时 日 月 星期”，例如 0 4 * * * 表示每天 04:00。'
    : 'Five fields: minute hour day month weekday; 0 4 * * * means daily at 04:00.';
  else if (field.key === 'CROSSPLAY_PLATFORMS') effect = zh
    ? '使用括号和逗号，例如 (Steam,Xbox,PS5,Mac)；删掉某平台会拒绝该平台连接。'
    : 'Use parentheses and commas, for example (Steam,Xbox,PS5,Mac).';
  else if (/MESSAGE$/.test(field.key)) effect = zh
    ? '修改文本只改变通知内容；留空会发送空消息或由镜像跳过，取决于对应启用开关。'
    : 'Changes notification text only; the matching enable switch controls sending.';
  else if (/URL$/.test(field.key)) effect = zh
    ? '必须是完整 http:// 或 https:// 地址；留空表示不使用专用地址。'
    : 'Must be an absolute http:// or https:// URL; blank disables the dedicated URL.';
  else effect = zh
    ? '按字段要求填写；文本没有“调大或调小”的含义。'
    : 'Enter the documented text value; size direction does not apply.';

  if (field.dependsOn) {
    effect += zh ? ` 仅在 ${field.dependsOn} 时生效。` : ` Effective only when ${field.dependsOn}.`;
  }
  return effect;
}

function settingHelp(field) {
  const doc = settingDoc(field);
  return {
    meaning: settingMeaning(field),
    effect: settingEffect(field),
    sourceLabel: currentLang === 'zh' ? doc.zh : doc.en,
    sourceUrl: doc.url
  };
}

function fieldDescription(field) {
  const help = settingHelp(field);
  return `${help.meaning} ${help.effect}`;
}

function sourceName(source) {
  const names = currentLang === 'zh'
    ? {game:'游戏', engine:'引擎', container:'容器'}
    : {game:'game', engine:'engine', container:'container'};
  return names[source] || source;
}

function renderSettings() {
  if (!FIELDS.length) return;
  const filter = $('searchInput').value.trim().toLowerCase();
  const selectedGroup = $('groupFilter').value;
  const modifiedOnly = $('modifiedOnly').checked;
  const showAdvanced = $('showAdvanced').checked;
  const groups = {};
  FIELDS.forEach(f => {
    const haystack = `${settingLabel(f)} ${f.key} ${fieldDescription(f)} ${f.source}`.toLowerCase();
    if (filter && !haystack.includes(filter)) return;
    if (selectedGroup && f.group !== selectedGroup) return;
    if (modifiedOnly && !envModified.has(f.key)) return;
    if (!showAdvanced && f.advanced && !selectedGroup && !filter && !envModified.has(f.key)) return;
    (groups[f.group] ||= []).push(f);
  });
  Object.values(groups).forEach(fields => fields.sort(compareFields));

  const grid = $('settingsGrid');
  const orderedGroups = GROUP_ORDER.filter(group => groups[group]);
  if (orderedGroups.length === 0) {
    grid.innerHTML = `<div style="color: var(--text-faint); padding: 40px; text-align: center; font-family: var(--mono); font-size: 14px;">${t('settings.noMatch')} "${escapeHtml(filter)}"</div>`;
    updateSettingsSummary(0);
    return;
  }

  // When actively searching, auto-expand all visible groups so matches are seen.
  const searching = !!filter;
  const collapsedState = loadSettingsCollapseState();

  grid.innerHTML = orderedGroups.map(group => {
    const fields = groups[group];
    const collapsed = searching ? false : !!collapsedState[group];
    const modifiedInGroup = fields.filter(f => envModified.has(f.key)).length;
    const chevronSvg = '<svg class="settings-group-chevron" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="6 9 12 15 18 9"></polyline></svg>';
    const modifiedBadge = modifiedInGroup > 0
      ? `<span class="settings-group-modified" title="${modifiedInGroup} ${currentLang === 'zh' ? '项已修改' : 'modified'}">${modifiedInGroup}</span>`
      : '';
    return `<div class="settings-group${collapsed ? ' collapsed' : ''}" data-group="${escapeHtml(group)}">
      <div class="settings-group-header" role="button" tabindex="0" aria-expanded="${collapsed ? 'false' : 'true'}" title="${t('settings.collapseHint')}">
        ${chevronSvg}
        <span class="settings-group-title">${escapeHtml(groupLabel(group))}</span>
        <span class="settings-group-count">${fields.length} ${currentLang === 'zh' ? '项' : 'fields'}</span>
        ${modifiedBadge}
      </div>
      <div class="settings-group-body">
        ${fields.map(f => renderField(f)).join('')}
      </div>
    </div>`;
  }).join('');

  // Bind header click/keyboard toggle.
  grid.querySelectorAll('.settings-group-header').forEach(header => {
    const groupEl = header.parentElement;
    const groupName = groupEl.dataset.group;
    const toggle = () => {
      const isCollapsed = groupEl.classList.toggle('collapsed');
      header.setAttribute('aria-expanded', isCollapsed ? 'false' : 'true');
      saveSettingsCollapseState(groupName, isCollapsed);
    };
    header.addEventListener('click', toggle);
    header.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); toggle(); }
    });
  });

  orderedGroups.flatMap(group => groups[group]).forEach(f => {
    const el = $('f_' + f.key);
    if (!el) return;
    el.addEventListener(f.type === 'boolean' || f.type === 'choice' ? 'change' : 'input', () => markModified(f.key));
  });
  grid.querySelectorAll('[data-clear-secret]').forEach(button => {
    button.addEventListener('click', () => clearSecret(button.dataset.clearSecret));
  });
  updateSettingsSummary(orderedGroups.reduce((sum, group) => sum + groups[group].length, 0));
  updateSaveDock();
}

const SETTINGS_COLLAPSE_KEY = 'palworld_settings_collapsed_groups';

function loadSettingsCollapseState() {
  try {
    const raw = localStorage.getItem(SETTINGS_COLLAPSE_KEY);
    if (!raw) return {};
    const parsed = JSON.parse(raw);
    return (parsed && typeof parsed === 'object') ? parsed : {};
  } catch { return {}; }
}

function saveSettingsCollapseState(group, collapsed) {
  const state = loadSettingsCollapseState();
  if (collapsed) { state[group] = true; } else { delete state[group]; }
  try { localStorage.setItem(SETTINGS_COLLAPSE_KEY, JSON.stringify(state)); } catch {}
}

function setAllSettingsGroups(collapsed) {
  const grid = $('settingsGrid');
  if (!grid) return;
  const state = {};
  grid.querySelectorAll('.settings-group').forEach(groupEl => {
    const groupName = groupEl.dataset.group;
    if (!groupName) return;
    if (collapsed) {
      groupEl.classList.add('collapsed');
      state[groupName] = true;
    } else {
      groupEl.classList.remove('collapsed');
    }
    const header = groupEl.querySelector('.settings-group-header');
    if (header) header.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
  });
  try { localStorage.setItem(SETTINGS_COLLAPSE_KEY, JSON.stringify(state)); } catch {}
}

function renderField(f) {
  const val = effectiveSettingValue(f.key);
  const isModified = envModified.has(f.key);
  const modClass = isModified ? ' modified' : '';
  const id = 'f_' + f.key;
  const dependencyOff = !dependencyEnabled(f);
  const explicit = explicitSettings.has(f.key);
  const configuredSecret = configuredSecrets.has(f.key);
  const label = settingLabel(f);
  const help = settingHelp(f);
  const min = Object.prototype.hasOwnProperty.call(f, 'min') ? ` min="${f.min}"` : '';
  const max = Object.prototype.hasOwnProperty.call(f, 'max') ? ` max="${f.max}"` : '';
  const step = Object.prototype.hasOwnProperty.call(f, 'step') ? f.step : (f.type === 'number' ? 'any' : 1);
  let input;
  if (f.type === 'boolean') {
    const checked = String(val).toLowerCase() === 'true';
    input = `<label class="field-row toggle-row" for="${id}">
      <span class="toggle ${checked ? 'on' : ''}">
        <input type="checkbox" id="${id}" ${checked ? 'checked' : ''} style="opacity:0;width:1px;height:1px;position:absolute;">
      </span>
      <span class="toggle-row-label">${checked ? (currentLang === 'zh' ? '启用' : 'Enabled') : (currentLang === 'zh' ? '禁用' : 'Disabled')}</span>
    </label>`;
  } else if (f.type === 'choice') {
    input = `<select id="${id}" data-key="${f.key}">${(f.options || []).map(o => `<option value="${escapeHtml(o)}" ${String(o)===String(val)?'selected':''}>${escapeHtml(o)}</option>`).join('')}</select>`;
  } else if (f.type === 'secret') {
    const placeholder = configuredSecret
      ? (currentLang === 'zh' ? '已设置；输入新值才会替换' : 'Configured; enter a new value to replace')
      : (currentLang === 'zh' ? '未设置' : 'Not configured');
    const canClear = f.key !== 'ADMIN_PASSWORD' && configuredSecret;
    input = `<div class="secret-row">
      <input type="password" id="${id}" data-key="${f.key}" value="${isModified && val ? escapeHtml(val) : ''}" placeholder="${escapeHtml(placeholder)}" autocomplete="new-password" minlength="${f.minLength ?? 0}" maxlength="${f.maxLength ?? 256}">
      ${canClear ? `<button type="button" class="btn compact" data-clear-secret="${f.key}">${currentLang === 'zh' ? '清除' : 'Clear'}</button>` : ''}
    </div>`;
  } else if (f.type === 'integer' || f.type === 'number') {
    input = `<input type="number" id="${id}" data-key="${f.key}" value="${escapeHtml(val)}" step="${step}"${min}${max}>`;
  } else {
    input = `<input type="text" id="${id}" data-key="${f.key}" value="${escapeHtml(val)}" minlength="${f.minLength ?? 0}" maxlength="${f.maxLength ?? 256}">`;
  }
  return `<div class="field${modClass}${dependencyOff ? ' dependent-off' : ''}" data-fkey="${f.key}">
    <div class="field-topline">
      <span class="name">${escapeHtml(label)}</span>
      <span class="field-meta">
        <span class="source-chip">${escapeHtml(sourceName(f.source))}</span>
        ${explicit ? `<span class="explicit-chip">${currentLang === 'zh' ? '已显式配置' : 'explicit'}</span>` : ''}
        ${f.risk !== 'normal' ? `<span class="risk-chip ${escapeHtml(f.risk)}">${f.risk === 'danger' ? (currentLang==='zh'?'高风险':'danger') : (currentLang==='zh'?'需谨慎':'caution')}</span>` : ''}
      </span>
    </div>
    <div class="field-key">${escapeHtml(f.key)} · default ${escapeHtml(f.default ?? '')}</div>
    ${input}
    <div class="field-help" data-setting-help="${escapeHtml(f.key)}">
      <div class="field-help-line">
        <span class="field-help-label">${currentLang === 'zh' ? '作用' : 'Meaning'}</span>
        <span>${escapeHtml(help.meaning)}</span>
      </div>
      <div class="field-help-line">
        <span class="field-help-label">${currentLang === 'zh' ? '怎么调' : 'Effect'}</span>
        <span class="field-help-effect">${escapeHtml(help.effect)}</span>
      </div>
      <a class="field-help-source" href="${escapeHtml(help.sourceUrl)}" target="_blank" rel="noreferrer">${escapeHtml(help.sourceLabel)}</a>
    </div>
  </div>`;
}

function markModified(key) {
  const field = FIELDS.find(f => f.key === key);
  const input = $('f_' + key);
  if (!field || !input) return;
  const value = field.type === 'boolean' ? (input.checked ? 'true' : 'false') : input.value;
  if (field.type === 'secret') {
    if (value) {
      envDraft[key] = value;
      envModified.add(key);
    } else if (envDraft[key] !== '') {
      delete envDraft[key];
      envModified.delete(key);
    }
  } else if (String(value) === String(envValues[key] ?? field.default ?? '')) {
    delete envDraft[key];
    envModified.delete(key);
  } else {
    envDraft[key] = value;
    envModified.add(key);
  }
  const fieldEl = document.querySelector(`[data-fkey="${key}"]`);
  if (fieldEl) fieldEl.classList.toggle('modified', envModified.has(key));
  if (field.type === 'boolean' || field.type === 'choice') renderSettings();
  else updateSaveDock();
}

function clearSecret(key) {
  envDraft[key] = '';
  envModified.add(key);
  renderSettings();
}

function updateSettingsSummary(visibleCount) {
  const advancedHidden = !$('showAdvanced').checked;
  const excludedCount = settingsExclusions.reduce((sum, item) => sum + (item.keys?.length || 0), 0);
  const zh = currentLang === 'zh';
  $('settingsSummary').innerHTML = `
    <span class="summary-chip"><strong>${FIELDS.length}</strong> ${zh?'项当前平台支持':'supported on this platform'}</span>
    <span class="summary-chip"><strong>${visibleCount}</strong> ${zh?'项当前显示':'visible'}</span>
    <span class="summary-chip"><strong>${explicitSettings.size}</strong> ${zh?'项显式写入 .env':'explicit in .env'}</span>
    <span class="summary-chip"><strong>${envModified.size}</strong> ${zh?'项待应用':'pending'}</span>
    <span class="summary-chip"><strong>${excludedCount}</strong> ${zh?'项 ARM64 专用已排除':'ARM64-only excluded'}</span>
    ${advancedHidden ? `<span class="summary-chip">${zh?'高级项当前折叠':'advanced fields collapsed'}</span>` : ''}`;
  $('modifiedOnlyLabel').textContent = zh ? '只看已修改' : 'Modified only';
  $('showAdvancedLabel').textContent = zh ? '显示高级项' : 'Show advanced';
  $('settingsNotice').textContent = t('settings.notice');
}

function updateSaveDock() {
  $('saveDock').classList.toggle('show', envModified.size > 0);
  $('modifiedCount').textContent = envModified.size;
  $('modifiedCountLabel').textContent = currentLang === 'zh' ? '项修改等待应用' : 'changes pending';
}

$('searchInput').addEventListener('input', renderSettings);
$('groupFilter').addEventListener('change', renderSettings);
$('modifiedOnly').addEventListener('change', renderSettings);
$('showAdvanced').addEventListener('change', () => {
  localStorage.setItem('pw-show-advanced', $('showAdvanced').checked ? '1' : '0');
  renderSettings();
});
$('showAdvanced').checked = localStorage.getItem('pw-show-advanced') === '1';

function resetSettingsDraft() {
  envDraft = {};
  envModified.clear();
  renderSettings();
  toast(t('toast.reset'), 'info', t('toast.reset'));
}
$('btnResetSettings').addEventListener('click', resetSettingsDraft);
$('btnResetDock').addEventListener('click', resetSettingsDraft);
$('btnCollapseAll').addEventListener('click', () => setAllSettingsGroups(true));
$('btnExpandAll').addEventListener('click', () => setAllSettingsGroups(false));

$('btnSaveSettings').addEventListener('click', async () => {
  if (envModified.size === 0) {
    toast(t('settings.noChanges'), 'warn', t('toast.noChanges'));
    return;
  }
  const riskCount = [...envModified].filter(key => ['caution','danger'].includes(FIELDS.find(f => f.key === key)?.risk)).length;
  const body = t('modal.save.body', {n: envModified.size}) +
    (riskCount ? (currentLang === 'zh' ? ` 其中 ${riskCount} 项属于需谨慎配置。` : ` ${riskCount} change(s) are marked caution/danger.`) : '');
  const ok = await showModal(t('modal.save.title'), body);
  if (!ok) return;

  showLoading(t('loading.savingEnv'));
  const payload = {};
  envModified.forEach(key => { payload[key] = envDraft[key]; });
  try {
    const r = await api('/api/env', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(payload) });
    if (r.ok) {
      if (!Array.isArray(r.changed) || r.changed.length === 0) {
        toast(t('settings.noChanges'), 'info', t('toast.noChanges'));
        await loadEnv();
        hideLoading();
        return;
      }
      toast(t('settings.saved', {n: envModified.size}) + ' ' + t('toast.reloading'), 'success', t('toast.saved'));
      const restart = await api('/api/restart', { method: 'POST' });
      if (restart.ok) {
        toast(t('settings.restarted'), 'success', t('toast.containerRestarted'));
        await loadEnv();
        setTimeout(refreshState, 2500);
      } else {
        toast(restart.error || t('settings.restartFailed'), 'error', t('settings.restartFailed'));
        await loadEnv();
      }
    } else {
      toast(r.error || t('settings.saveFailed'), 'error', t('settings.saveFailed'));
    }
  } catch (e) {
    toast(e.message, 'error', t('common.networkError'));
  }
  hideLoading();
});

// ===== Backup list =====
async function loadBackups() {
  try {
    const r = await api('/api/backups');
    if (!r.ok) { $('backupList').innerHTML = '<div class="backup-empty">' + escapeHtml(t('common.error') + ': ' + r.error) + '</div>'; return; }
    if (r.backups.length === 0) {
      $('backupList').innerHTML = '<div class="backup-empty">' + t('common.noBackups') + '</div>';
      return;
    }
    const dlSvg = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>';
    $('backupList').innerHTML = r.backups.map(b => {
      const safeName = encodeURIComponent(b.name);
      return `<div class="backup-card">
        <div class="backup-card-info">
          <div class="backup-card-name">${escapeHtml(b.name)}</div>
          <div class="backup-card-meta">
            <span>${escapeHtml(b.time)}</span>
            <span class="backup-card-size">${escapeHtml(b.sizeMb)} MB</span>
          </div>
        </div>
        <a class="backup-card-download" href="/api/backups/download?name=${safeName}" download="${escapeHtml(b.name)}" title="${escapeHtml(t('backup.download'))}">
          ${dlSvg}<span>${escapeHtml(t('backup.download'))}</span>
        </a>
      </div>`;
    }).join('');
  } catch (e) {
    $('backupList').innerHTML = '<div class="backup-empty">' + escapeHtml(t('common.error') + ': ' + e.message) + '</div>';
  }
}

// ===== Reserved Mod manager =====
function renderMods() {
  if (!modState) return;
  const managerEnabled = Boolean(modState.managerEnabled);
  const runtimeSupported = Boolean(modState.runtimeSupported);
  const operational = Boolean(modState.operational);
  const errors = Number(modState.validationErrors || 0);
  const enabled = Number(modState.enabledMods || 0);

  $('modMetricManager').textContent = t(managerEnabled ? 'mods.value.on' : 'mods.value.off');
  $('modMetricRuntime').textContent = modState.runtime || '—';
  $('modMetricConfigured').textContent = String(modState.totalMods || 0);
  $('modMetricUpdates').textContent = String(modState.updatesAvailable || 0);

  const badge = $('modStateBadge');
  const guard = $('modGuard');
  const guardCode = $('modGuardCode');
  const guardTitle = $('modGuardTitle');
  badge.classList.remove('ready');
  guard.classList.remove('ready');
  if (!runtimeSupported) {
    badge.textContent = t('mods.state.blocked');
    guardCode.textContent = 'FAIL CLOSED';
    guardTitle.textContent = t('mods.guard.title');
    $('modGuardReason').textContent = t('mods.reason.runtime');
  } else if (!managerEnabled) {
    badge.textContent = t('mods.state.disabled');
    guardCode.textContent = 'FAIL CLOSED';
    guardTitle.textContent = t('mods.guard.title');
    $('modGuardReason').textContent = t('mods.reason.disabled');
  } else {
    badge.textContent = t('mods.state.ready');
    badge.classList.add('ready');
    guard.classList.add('ready');
    guardCode.textContent = 'READY';
    guardTitle.textContent = t('mods.guard.title.ready');
    $('modGuardReason').textContent = t('mods.reason.ready');
  }

  $('btnModSync').disabled = !(operational && errors === 0 && enabled > 0);
  const mods = Array.isArray(modState.mods) ? modState.mods : [];
  if (mods.length === 0) {
    $('modList').innerHTML = `<div class="mod-empty">${escapeHtml(t('mods.empty'))}</div>`;
    return;
  }
  $('modList').innerHTML = mods.map(mod => {
    let statusKey = 'mods.status.approved';
    if (mod.error) statusKey = 'mods.status.error';
    else if (!mod.enabled) statusKey = 'mods.status.inactive';
    else if (!mod.sourceExists) statusKey = 'mods.status.missing';
    else if (!mod.hashApproved) statusKey = 'mods.status.approval';
    else if (mod.installed) statusKey = 'mods.status.installed';
    const name = mod.displayName || mod.packageName || mod.workshopId;
    const version = mod.sourceVersion ? ` · v${escapeHtml(mod.sourceVersion)}` : '';
    return `<div class="mod-item">
      <div>
        <div class="mod-item-name">${escapeHtml(name)}</div>
        <div class="mod-item-meta">Workshop ${escapeHtml(mod.workshopId)} · ${escapeHtml(mod.packageName)}${version}</div>
      </div>
      <div class="mod-item-meta">${escapeHtml(t(statusKey))}</div>
    </div>`;
  }).join('');
}

async function loadMods(check = false) {
  if (check) showLoading(t('loading.mods'));
  try {
    modState = check
      ? await api('/api/mods/check', {method: 'POST'})
      : await api('/api/mods');
    renderMods();
    if (check) toast(t('mods.check.ok'), 'success', t('toast.ok'));
  } catch (e) {
    $('modList').innerHTML = `<div class="mod-empty">${escapeHtml(t('common.error') + ': ' + e.message)}</div>`;
    if (check) toast(e.message, 'error', t('common.error'));
  } finally {
    if (check) hideLoading();
  }
}

$('btnModCheck').addEventListener('click', () => loadMods(true));
$('btnModSync').addEventListener('click', async () => {
  const confirmed = await showModal(t('mods.modal.sync.title'), t('mods.modal.sync.body'));
  if (!confirmed) return;
  showLoading(t('loading.mods'));
  try {
    const result = await api('/api/mods/sync', {method: 'POST'});
    modState = result;
    renderMods();
    if (result.ok && result.changed) {
      toast(t('mods.sync.ok'), 'success', t('toast.ok'));
    } else {
      toast(result.error || t('mods.sync.blocked'), 'warn', t('mods.state.disabled'));
    }
  } catch (e) {
    toast(e.message, 'error', t('common.error'));
  } finally {
    hideLoading();
  }
});

// ===== Runtime panel =====
let runtimeState = null;
let runtimeTaskPollTimer = null;
let runtimeActiveTaskId = null;

function formatBytes(n) {
  const bytes = Number(n) || 0;
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
  if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  return (bytes / (1024 * 1024 * 1024)).toFixed(2) + ' GB';
}

function formatTimestamp(ts) {
  if (!ts) return '—';
  try {
    const d = new Date(ts);
    if (isNaN(d.getTime())) return String(ts);
    return d.toLocaleString();
  } catch (e) { return String(ts); }
}

async function loadRuntime() {
  try {
    const [state, snaps] = await Promise.all([
      api('/api/runtime'),
      api('/api/snapshots')
    ]);
    runtimeState = state;
    renderRuntimeState(state);
    renderSnapshots(snaps);
    renderRuntimeWarnings(state);
  } catch (e) {
    $('runtimeJunction').innerHTML = `<div class="mod-empty">${escapeHtml(t('common.error') + ': ' + e.message)}</div>`;
    $('runtimeSnapshotList').innerHTML = `<div class="mod-empty">${escapeHtml(t('common.error') + ': ' + e.message)}</div>`;
  }
}

function renderRuntimeState(state) {
  if (!state || !state.ok) return;
  const zh = currentLang === 'zh';
  const r = state.runtime || {};
  $('runtimeActive').textContent = String(r.active || 'none').toUpperCase();
  $('runtimeVersion').textContent = (zh ? '版本 ' : 'version ') + (r.version || '—');
  $('runtimePid').textContent = r.pid || '—';
  $('runtimeStartedAt').textContent = (zh ? '启动于 ' : 'started ') + (r.startedAt ? formatTimestamp(r.startedAt) : '—');

  const snaps = state.snapshots || {};
  $('runtimeSnapCount').textContent = String(snaps.total || 0);
  $('runtimeSnapSize').textContent = formatBytes(snaps.totalBytes || 0);

  const ini = state.iniCompile || {};
  $('runtimeIniStatus').textContent = String(ini.status || '—');
  $('runtimeIniLastRun').textContent = (zh ? '上次执行 ' : 'last ') + (ini.lastRun ? formatTimestamp(ini.lastRun) : '—');

  // Junction card
  const j = state.junction;
  const jEl = $('runtimeJunction');
  if (!j) {
    jEl.innerHTML = `<div class="mod-empty">${zh ? '存档连接点信息不可用' : 'Save junction information is unavailable'}</div>`;
  } else if (j.error) {
    jEl.innerHTML = `<div class="mod-empty" style="color: var(--danger);">${zh ? '存档连接点错误：' : 'Save junction error: '}${escapeHtml(j.error)}</div>`;
  } else {
    const okBadges = j.ok
      ? '<span style="color: var(--accent); font-weight: 600;">OK</span>'
      : '<span style="color: var(--danger); font-weight: 600;">异常</span>';
    jEl.innerHTML = `
      <div style="display: grid; gap: 6px; font-size: 13px;">
        <div><b>${zh ? '存在：' : 'exists:'}</b> ${j.exists ? (zh ? '是' : 'yes') : (zh ? '否' : 'no')} · <b>${zh ? '类型：' : 'link type:'}</b> ${escapeHtml(j.linkType || '—')}</div>
        <div><b>${zh ? '目标：' : 'target:'}</b> ${escapeHtml(j.target || '—')}</div>
        <div><b>${zh ? '解析路径：' : 'resolved:'}</b> ${escapeHtml(j.resolved || '—')}</div>
        <div><b>${zh ? '状态：' : 'status:'}</b> ${okBadges}</div>
      </div>`;
  }

  updateRuntimeSwitchControls(state);

  // Snapshot controls are disabled only while a switch task owns the runtime.
  const switching = !!r.switching;
  ['btnSnapLight', 'btnSnapFull'].forEach(id => {
    const b = $(id);
    if (b) b.disabled = switching;
  });
}

function updateRuntimeSwitchControls(state) {
  const r = state && state.runtime ? state.runtime : {};
  const active = String(r.active || 'none');
  const switching = !!r.switching;
  const targets = [
    { id: 'btnSwitchDocker', target: 'docker', normalKey: 'runtime.btn.docker', currentKey: 'runtime.btn.current.docker' },
    { id: 'btnSwitchWindows', target: 'windows', normalKey: 'runtime.btn.windows', currentKey: 'runtime.btn.current.windows' },
  ];
  targets.forEach(({ id, target, normalKey, currentKey }) => {
    const button = $(id);
    if (!button) return;
    const isCurrent = active === target;
    button.disabled = switching || isCurrent;
    button.classList.toggle('is-current-runtime', isCurrent);
    button.setAttribute('aria-disabled', String(switching || isCurrent));
    button.textContent = t(isCurrent ? currentKey : normalKey);
    button.title = isCurrent
      ? (currentLang === 'zh' ? '当前运行时无需切换。' : 'The current runtime does not need a switch.')
      : '';
  });
  const hint = $('runtimeSwitchHint');
  if (hint) {
    const runtimeName = active === 'windows'
      ? (currentLang === 'zh' ? 'Windows 原生服务端' : 'Windows Native')
      : active === 'docker' ? 'Docker' : (currentLang === 'zh' ? '无运行时' : 'no runtime');
    hint.textContent = switching
      ? (currentLang === 'zh' ? '运行时切换进行中，所有运行时写操作已锁定。' : 'A runtime switch is in progress; runtime write actions are locked.')
      : t('runtime.switch.hint', { runtime: runtimeName });
  }
}

function renderRuntimeWarnings(state) {
  const warnEl = $('runtimeWarnings');
  const warnings = [];
  if (state && state.runtime && state.runtime.switching) {
    warnings.push('运行时切换进行中，写操作已被禁用。');
  }
  if (state && state.iniCompile && state.iniCompile.driftDetected) {
    warnings.push('检测到 INI 配置漂移：.env 修改时间晚于 INI 编译时间，请重编译 INI 或重新保存设置。');
  }
  if (state && state.junction && state.junction.exists && !state.junction.ok) {
    warnings.push('SaveGames junction 异常，Windows 运行时可能无法访问存档。');
  }
  warnEl.innerHTML = warnings.map(w => `<div class="warning-item">${escapeHtml(w)}</div>`).join('');
}

function renderSnapshots(data) {
  const listEl = $('runtimeSnapshotList');
  if (!data || !data.ok || !data.snapshots || data.snapshots.length === 0) {
    listEl.innerHTML = `<div class="mod-empty">${currentLang === 'zh' ? '暂无快照' : 'No snapshots yet'}</div>`;
    return;
  }
  const rows = data.snapshots.map(s => {
    const typeColor = s.type === 'Full' ? 'var(--accent)' : 'var(--info)';
    return `
      <div class="mod-row" style="display: flex; gap: 10px; align-items: center; padding: 8px 4px; border-bottom: 1px solid var(--border);">
        <span style="font-family: var(--mono); font-size: 12px; color: ${typeColor}; font-weight: 600; min-width: 50px;">${escapeHtml(s.type || '—')}</span>
        <div style="flex: 1; min-width: 0;">
          <div style="font-size: 13px; word-break: break-all;">${escapeHtml(s.name || '')}</div>
          <div style="font-size: 11px; opacity: 0.7;">
            ${escapeHtml(s.phase || '—')} · ${formatTimestamp(s.createdAt)} · ${formatBytes(s.sizeBytes)}
            ${s.from && s.to ? ' · ' + escapeHtml(s.from) + ' → ' + escapeHtml(s.to) : ''}
          </div>
        </div>
        <button class="btn compact" data-snapshot-restore="${escapeHtml(s.name)}" data-i18n="runtime.btn.restore">恢复</button>
      </div>`;
  }).join('');
  listEl.innerHTML = rows;
  const switching = !!(runtimeState && runtimeState.runtime && runtimeState.runtime.switching);
  listEl.querySelectorAll('[data-snapshot-restore]').forEach(btn => {
    btn.disabled = switching;
    btn.addEventListener('click', () => {
      const name = btn.getAttribute('data-snapshot-restore');
      restoreSnapshot(name);
    });
  });
}

async function switchRuntime(target) {
  const fullSnapshot = $('chkFullSnapshot').checked;
  const active = runtimeState && runtimeState.runtime ? runtimeState.runtime.active : 'none';
  if (active === target) {
    toast('当前已是 ' + target + ' 运行时', 'warn');
    return;
  }
  const confirmMsg = currentLang === 'zh'
    ? `确认从 ${active} 切换到 ${target}？切换前会自动创建${fullSnapshot ? '完整' : 'Light'}快照并停止当前运行时。`
    : `Switch from ${active} to ${target}? A ${fullSnapshot ? 'full' : 'light'} snapshot will be created and the current runtime will be stopped.`;
  const confirmed = await showModal(t('runtime.modal.switch.title'), confirmMsg);
  if (!confirmed) return;
  showLoading(currentLang === 'zh' ? '正在切换运行时…' : 'Switching runtime…');
  try {
    const result = await api('/api/runtime/switch', {
      method: 'POST',
      body: JSON.stringify({ to: target, force: false, fullSnapshot })
    });
    if (result && result.taskId) {
      runtimeActiveTaskId = result.taskId;
      startTaskPolling(result.taskId, '切换到 ' + target);
      toast(currentLang === 'zh' ? '切换任务已启动' : 'Switch task started', 'success');
    } else {
      toast(result.error || '切换失败', 'error');
    }
  } catch (e) {
    toast(e.message, 'error');
  } finally {
    hideLoading();
  }
}

async function createSnapshot(type) {
  showLoading(currentLang === 'zh' ? '正在创建快照…' : 'Creating snapshot…');
  try {
    const result = await api('/api/runtime/snapshot', {
      method: 'POST',
      body: JSON.stringify({ type })
    });
    if (result && result.taskId) {
      runtimeActiveTaskId = result.taskId;
      startTaskPolling(result.taskId, '创建 ' + type + ' 快照');
      toast(currentLang === 'zh' ? '快照任务已启动' : 'Snapshot task started', 'success');
    } else {
      toast(result.error || '快照创建失败', 'error');
    }
  } catch (e) {
    toast(e.message, 'error');
  } finally {
    hideLoading();
  }
}

async function restoreSnapshot(name) {
  const active = runtimeState && runtimeState.runtime ? runtimeState.runtime.active : 'none';
  if (active !== 'none') {
    toast(currentLang === 'zh' ? '恢复前必须先停止当前运行时' : 'Stop the active runtime before restore', 'warn');
    return;
  }
  const confirmMsg = currentLang === 'zh'
    ? `确认从快照 ${name} 恢复？当前存档和配置将被替换，恢复前会自动创建临时快照。`
    : `Restore from snapshot ${name}? Current save and config will be replaced (a temporary snapshot is taken first).`;
  const confirmed = await showModal(t('runtime.modal.restore.title'), confirmMsg);
  if (!confirmed) return;
  showLoading(currentLang === 'zh' ? '正在恢复快照…' : 'Restoring snapshot…');
  try {
    const result = await api('/api/runtime/restore', {
      method: 'POST',
      body: JSON.stringify({ name, force: false })
    });
    if (result && result.taskId) {
      runtimeActiveTaskId = result.taskId;
      startTaskPolling(result.taskId, '恢复快照 ' + name);
      toast(currentLang === 'zh' ? '恢复任务已启动' : 'Restore task started', 'success');
    } else {
      toast(result.error || '恢复失败', 'error');
    }
  } catch (e) {
    toast(e.message, 'error');
  } finally {
    hideLoading();
  }
}

function startTaskPolling(taskId, title) {
  if (runtimeTaskPollTimer) clearInterval(runtimeTaskPollTimer);
  const bar = $('runtimeTaskBar');
  bar.hidden = false;
  $('runtimeTaskTitle').textContent = title;
  $('runtimeTaskDetail').textContent = 'taskId: ' + taskId;
  $('runtimeTaskStatus').textContent = currentLang === 'zh' ? '运行中' : 'running';

  const poll = async () => {
    try {
      const task = await api('/api/runtime/task?id=' + encodeURIComponent(taskId));
      if (!task) return;
    const taskStatus = String(task.status || 'running');
    $('runtimeTaskStatus').textContent = currentLang === 'zh'
      ? ({ running: '运行中', completed: '已完成', failed: '失败' }[taskStatus] || taskStatus)
      : taskStatus;
      if (task.status === 'completed' || task.status === 'failed') {
        clearInterval(runtimeTaskPollTimer);
        runtimeTaskPollTimer = null;
        runtimeActiveTaskId = null;
        const ok = task.status === 'completed';
        const detail = currentLang === 'zh'
          ? (ok ? '任务完成（退出码 ' + task.exitCode + '）' : '任务失败（退出码 ' + task.exitCode + '）')
          : (ok ? 'Task completed (exit ' + task.exitCode + ')' : 'Task failed (exit ' + task.exitCode + ')');
        $('runtimeTaskDetail').textContent = detail;
        toast(detail, ok ? 'success' : 'error');
        // Refresh runtime view + dashboard
        loadRuntime();
        refreshState();
        // Auto-hide the bar after 8s
        setTimeout(() => { $('runtimeTaskBar').hidden = true; }, 8000);
      }
    } catch (e) {
      // Keep polling; transient errors are tolerated
    }
  };
  poll();
  runtimeTaskPollTimer = setInterval(poll, 3000);
}

$('btnRefreshRuntime').addEventListener('click', () => loadRuntime());
$('btnSwitchDocker').addEventListener('click', () => switchRuntime('docker'));
$('btnSwitchWindows').addEventListener('click', () => switchRuntime('windows'));
$('btnSnapLight').addEventListener('click', () => createSnapshot('Light'));
$('btnSnapFull').addEventListener('click', () => createSnapshot('Full'));

// ===== Init =====
$('panelAddressLabel').textContent = location.host;
$('langToggle').addEventListener('click', toggleLang);
$('themeToggle').addEventListener('click', toggleTheme);
refreshState();
loadMiniLog();
loadEnv();
setInterval(refreshState, 5000);
setInterval(loadMiniLog, 30000);
