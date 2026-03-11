//
//  EmojiPickerSheet.swift
//  break-even-ios
//
//  Created by Rudra Das on 2025-01-16.
//

import SwiftUI

// MARK: - Emoji Category

struct EmojiCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let emojis: [String]
}

// MARK: - Emoji Store

enum EmojiStore {
    
    static let categories: [EmojiCategory] = [
        smileysAndPeople,
        animalsAndNature,
        foodAndDrink,
        activities,
        travelAndPlaces,
        objects,
        symbols,
        flags
    ]
    
    static let smileysAndPeople = EmojiCategory(
        id: "smileys",
        name: "Smileys & People",
        symbol: "face.smiling",
        emojis: [
            "😀","😃","😄","😁","😆","🥹","😅","🤣","😂","🙂",
            "🙃","😉","😊","😇","🥰","😍","🤩","😘","😗","☺️",
            "😚","😙","🥲","😋","😛","😜","🤪","😝","🤑","🤗",
            "🤭","🤫","🤔","🫡","🤐","🤨","😐","😑","😶","🫥",
            "😏","😒","🙄","😬","🤥","🫨","😌","😔","😪","🤤",
            "😴","😷","🤒","🤕","🤢","🤮","🤧","🥵","🥶","🥴",
            "😵","🤯","🤠","🥳","🥸","😎","🤓","🧐","😕","🫤",
            "😟","🙁","☹️","😮","😯","😲","😳","🥺","😦","😧",
            "😨","😰","😥","😢","😭","😱","😖","😣","😞","😓",
            "😩","😫","🥱","😤","😡","😠","🤬","😈","👿","💀",
            "☠️","💩","🤡","👹","👺","👻","👽","👾","🤖","😺",
            "😸","😹","😻","😼","😽","🙀","😿","😾","🙈","🙉",
            "🙊","👋","🤚","🖐️","✋","🖖","🫱","🫲","🫳","🫴",
            "🫷","🫸","👌","🤌","🤏","✌️","🤞","🫰","🤟","🤘",
            "🤙","👈","👉","👆","🖕","👇","☝️","🫵","👍","👎",
            "✊","👊","🤛","🤜","👏","🙌","🫶","👐","🤲","🤝",
            "🙏","✍️","💅","🤳","💪","🦾","🦿","🦵","🦶","👂",
            "🦻","👃","🧠","🫀","🫁","🦷","🦴","👀","👁️","👅",
            "👄","🫦","👶","🧒","👦","👧","🧑","👱","👨","🧔",
            "👩","🧓","👴","👵","👮","💂","🕵️","👷","🫅","🤴",
            "👸","👳","👲","🧕","🤵","👰","🤰","🫄","🤱","👼",
            "🎅","🤶","🦸","🦹","🧙","🧚","🧛","🧜","🧝","🧞",
            "🧟","🧌","💆","💇","🚶","🧍","🧎","🏃","💃","🕺",
            "🕴️","👯","🧖","🧗","🤸","⛹️","🏋️","🤼","🤽","🤾",
            "🤺","⛷️","🏂","🏌️","🏇","🏊","🚣","🏄","🧘","👪"
        ]
    )
    
    static let animalsAndNature = EmojiCategory(
        id: "animals",
        name: "Animals & Nature",
        symbol: "pawprint.fill",
        emojis: [
            "🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐻‍❄️","🐨",
            "🐯","🦁","🐮","🐷","🐽","🐸","🐵","🙈","🙉","🙊",
            "🐒","🐔","🐧","🐦","🐤","🐣","🐥","🦆","🦅","🦉",
            "🦇","🐺","🐗","🐴","🦄","🐝","🪱","🐛","🦋","🐌",
            "🐞","🐜","🪰","🪲","🪳","🦟","🦗","🕷️","🕸️","🦂",
            "🐢","🐍","🦎","🦖","🦕","🐙","🦑","🦐","🦞","🦀",
            "🪸","🐡","🐠","🐟","🐬","🐳","🐋","🦈","🦭","🐊",
            "🐅","🐆","🦓","🫏","🦍","🦧","🦣","🐘","🦛","🦏",
            "🐪","🐫","🦒","🦘","🦬","🐃","🐂","🐄","🐎","🐖",
            "🐏","🐑","🦙","🐐","🦌","🫎","🐕","🐩","🦮","🐈",
            "🐈‍⬛","🪿","🐓","🦃","🦤","🦚","🦜","🦢","🦩","🕊️",
            "🐇","🦝","🦨","🦡","🦫","🦦","🦥","🐁","🐀","🐿️",
            "🦔","🐾","🐉","🐲","🌵","🎄","🌲","🌳","🌴","🪵",
            "🌱","🌿","☘️","🍀","🎍","🪴","🎋","🍃","🍂","🍁",
            "🪻","🪷","🌺","🌸","🌼","🌻","🌞","🌝","🌛","🌜",
            "🌚","🌕","🌖","🌗","🌘","🌑","🌒","🌓","🌔","🌙",
            "🌎","🌍","🌏","🪐","💫","⭐","🌟","✨","⚡","☄️",
            "💥","🔥","🌪️","🌈","☀️","🌤️","⛅","🌥️","☁️","🌦️",
            "🌧️","⛈️","🌩️","🌨️","❄️","☃️","⛄","🌬️","💨","💧",
            "💦","🫧","☔","☂️","🌊","🌫️"
        ]
    )
    
    static let foodAndDrink = EmojiCategory(
        id: "food",
        name: "Food & Drink",
        symbol: "fork.knife",
        emojis: [
            "🍏","🍎","🍐","🍊","🍋","🍌","🍉","🍇","🍓","🫐",
            "🍈","🍒","🍑","🥭","🍍","🥥","🥝","🍅","🍆","🥑",
            "🫛","🥦","🥬","🥒","🌶️","🫑","🌽","🥕","🫒","🧄",
            "🧅","🥔","🍠","🫚","🥐","🥯","🍞","🫓","🥖","🧀",
            "🥚","🍳","🧈","🥞","🧇","🥓","🥩","🍗","🍖","🦴",
            "🌭","🍔","🍟","🍕","🫔","🌮","🌯","🥙","🧆","🥚",
            "🌰","🥜","🫘","🍝","🍜","🍲","🍛","🍣","🍱","🥟",
            "🦪","🍤","🍙","🍚","🍘","🍥","🥠","🥮","🍢","🍡",
            "🍧","🍨","🍦","🥧","🧁","🍰","🎂","🍮","🍭","🍬",
            "🍫","🍿","🍩","🍪","🍯","🥛","🍼","🍵","☕","🫖",
            "🧃","🥤","🧋","🍶","🍺","🍻","🥂","🍷","🥃","🍸",
            "🍹","🧉","🍾","🧊","🥄","🍴","🍽️","🥢","🧂"
        ]
    )
    
    static let activities = EmojiCategory(
        id: "activities",
        name: "Activities",
        symbol: "figure.run",
        emojis: [
            "⚽","🏀","🏈","⚾","🥎","🎾","🏐","🏉","🥏","🎱",
            "🪀","🏓","🏸","🏒","🏑","🥍","🏏","🪃","🥅","⛳",
            "🪁","🏹","🎣","🤿","🥊","🥋","🎽","🛹","🛼","🛷",
            "⛸️","🥌","🎿","⛷️","🏂","🪂","🏆","🥇","🥈","🥉",
            "🏅","🎖️","🏵️","🎗️","🎫","🎟️","🎪","🤹","🎭","🩰",
            "🎨","🎬","🎤","🎧","🎼","🎹","🥁","🪘","🎷","🎺",
            "🎸","🪕","🎻","🪗","🎲","♟️","🎯","🎳","🎮","🧩",
            "🪅","🪩","🪆","🎰","🎃","🎄","🎆","🎇","🧨","✨",
            "🎈","🎉","🎊","🎋","🎍","🎎","🎏","🎐","🎑","🧧",
            "🎀","🎁"
        ]
    )
    
    static let travelAndPlaces = EmojiCategory(
        id: "travel",
        name: "Travel & Places",
        symbol: "car.fill",
        emojis: [
            "🚗","🚕","🚙","🚌","🚎","🏎️","🚓","🚑","🚒","🚐",
            "🛻","🚚","🚛","🚜","🦯","🦽","🦼","🛴","🚲","🛵",
            "🏍️","🛺","🚨","🚔","🚍","🚘","🚖","🛞","🚡","🚠",
            "🚟","🚃","🚋","🚞","🚝","🚄","🚅","🚈","🚂","🚆",
            "🚇","🚊","🚉","✈️","🛫","🛬","🛩️","💺","🛰️","🚀",
            "🛸","🚁","🛶","⛵","🚤","🛥️","🛳️","⛴️","🚢","⚓",
            "🪝","⛽","🚧","🚦","🚥","🚏","🗺️","🗿","🗽","🗼",
            "🏰","🏯","🏟️","🎡","🎢","🎠","⛲","⛱️","🏖️","🏝️",
            "🏜️","🌋","⛰️","🏔️","🗻","🏕️","⛺","🏠","🏡","🏘️",
            "🏚️","🏗️","🏭","🏢","🏬","🏣","🏤","🏥","🏦","🏨",
            "🏪","🏫","🏩","💒","🏛️","⛪","🕌","🕍","🛕","🕋",
            "⛩️","🛤️","🛣️","🗾","🎑","🏞️","🌅","🌄","🌠","🎇",
            "🎆","🌇","🌆","🏙️","🌃","🌌","🌉","🌁"
        ]
    )
    
    static let objects = EmojiCategory(
        id: "objects",
        name: "Objects",
        symbol: "lightbulb.fill",
        emojis: [
            "⌚","📱","📲","💻","⌨️","🖥️","🖨️","🖱️","🖲️","🕹️",
            "🗜️","💽","💾","💿","📀","📼","📷","📸","📹","🎥",
            "📽️","🎞️","📞","☎️","📟","📠","📺","📻","🎙️","🎚️",
            "🎛️","🧭","⏱️","⏲️","⏰","🕰️","⌛","⏳","📡","🔋",
            "🪫","🔌","💡","🔦","🕯️","🪔","🧯","🛢️","💰","🪙",
            "💴","💵","💶","💷","🪪","💳","💎","⚖️","🪜","🧰",
            "🪛","🔧","🔩","⚙️","🪤","🧲","🔫","💣","🧨","🪓",
            "🔪","🗡️","🛡️","🪖","🔗","⛓️","🧪","🧫","🧬","🔬",
            "🔭","💉","🩸","💊","🩹","🩼","🩺","🚪","🛗","🪞",
            "🪟","🛏️","🛋️","🪑","🚽","🪠","🚿","🛁","🪒","🧴",
            "🧷","🧹","🧺","🧻","🪣","🧼","🪥","🧽","🛒","🚬",
            "⚰️","🪦","⚱️","🏺","🔮","📿","🧿","🪬","💈","⚗️",
            "🪈","📮","📪","📫","📬","📭","🗳️","📝","💼","📁",
            "📂","🗂️","📅","📆","🗒️","🗓️","📇","📈","📉","📊",
            "📋","📌","📍","📎","🖇️","📏","📐","✂️","🗃️","🗄️",
            "🗑️","🔒","🔓","🔏","🔐","🔑","🗝️","🔨","🪓","⛏️",
            "⚒️","🛠️","🗡️","⚔️","💣","🪃","🏹","🛡️","🪚","🔧",
            "🪛","🔩","⚙️","🗜️","⚖️","🦯","🔗","⛓️","🪝","🧰",
            "🧲","🪜"
        ]
    )
    
    static let symbols = EmojiCategory(
        id: "symbols",
        name: "Symbols",
        symbol: "heart.fill",
        emojis: [
            "❤️","🧡","💛","💚","💙","🩵","💜","🖤","🩶","🤍",
            "🤎","💔","❤️‍🔥","❤️‍🩹","❣️","💕","💞","💓","💗","💖",
            "💘","💝","💟","☮️","✝️","☪️","🕉️","☸️","✡️","🔯",
            "🕎","☯️","☦️","🛐","⛎","♈","♉","♊","♋","♌",
            "♍","♎","♏","♐","♑","♒","♓","🆔","⚛️","🉑",
            "☢️","☣️","📴","📳","🈶","🈚","🈸","🈺","🈷️","✴️",
            "🆚","💮","🉐","㊙️","㊗️","🈴","🈵","🈹","🈲","🅰️",
            "🅱️","🆎","🆑","🅾️","🆘","❌","⭕","🛑","⛔","📛",
            "🚫","💯","💢","♨️","🚷","🚯","🚳","🚱","🔞","📵",
            "🚭","❗","❕","❓","❔","‼️","⁉️","🔅","🔆","〽️",
            "⚠️","🚸","🔱","⚜️","🔰","♻️","✅","🈯","💹","❇️",
            "✳️","❎","🌐","💠","Ⓜ️","🌀","💤","🏧","🚾","♿",
            "🅿️","🛗","🈳","🈂️","🛂","🛃","🛄","🛅","🚹","🚺",
            "🚻","🚮","🎦","📶","🈁","🔣","ℹ️","🔤","🔡","🔠",
            "🆖","🆗","🆙","🆒","🆕","🆓","0️⃣","1️⃣","2️⃣","3️⃣",
            "4️⃣","5️⃣","6️⃣","7️⃣","8️⃣","9️⃣","🔟","🔢","#️⃣","*️⃣",
            "⏏️","▶️","⏸️","⏯️","⏹️","⏺️","⏭️","⏮️","⏩","⏪",
            "🔀","🔁","🔂","◀️","🔼","🔽","⏫","⏬","➡️","⬅️",
            "⬆️","⬇️","↗️","↘️","↙️","↖️","↕️","↔️","↪️","↩️",
            "⤴️","⤵️","🔃","🔄","🔙","🔚","🔛","🔜","🔝","🛐",
            "⚛️","🕉️","✡️","☸️","☯️","✝️","☦️","☪️","☮️","🕎",
            "🔯","♾️","🔘","🔳","🔲","🏁","🚩","🎌","🏴","🏳️",
            "🏳️‍🌈","🏳️‍⚧️","🏴‍☠️"
        ]
    )
    
    static let flags = EmojiCategory(
        id: "flags",
        name: "Flags",
        symbol: "flag.fill",
        emojis: [
            "🇦🇫","🇦🇱","🇩🇿","🇦🇸","🇦🇩","🇦🇴","🇦🇮","🇦🇶","🇦🇬","🇦🇷",
            "🇦🇲","🇦🇼","🇦🇺","🇦🇹","🇦🇿","🇧🇸","🇧🇭","🇧🇩","🇧🇧","🇧🇾",
            "🇧🇪","🇧🇿","🇧🇯","🇧🇲","🇧🇹","🇧🇴","🇧🇦","🇧🇼","🇧🇷","🇧🇳",
            "🇧🇬","🇧🇫","🇧🇮","🇰🇭","🇨🇲","🇨🇦","🇨🇻","🇨🇫","🇹🇩","🇨🇱",
            "🇨🇳","🇨🇴","🇰🇲","🇨🇬","🇨🇩","🇨🇷","🇭🇷","🇨🇺","🇨🇼","🇨🇾",
            "🇨🇿","🇩🇰","🇩🇯","🇩🇲","🇩🇴","🇪🇨","🇪🇬","🇸🇻","🇬🇶","🇪🇷",
            "🇪🇪","🇪🇹","🇫🇯","🇫🇮","🇫🇷","🇬🇦","🇬🇲","🇬🇪","🇩🇪","🇬🇭",
            "🇬🇷","🇬🇩","🇬🇺","🇬🇹","🇬🇳","🇬🇼","🇬🇾","🇭🇹","🇭🇳","🇭🇰",
            "🇭🇺","🇮🇸","🇮🇳","🇮🇩","🇮🇷","🇮🇶","🇮🇪","🇮🇱","🇮🇹","🇯🇲",
            "🇯🇵","🇯🇴","🇰🇿","🇰🇪","🇰🇮","🇽🇰","🇰🇼","🇰🇬","🇱🇦","🇱🇻",
            "🇱🇧","🇱🇸","🇱🇷","🇱🇾","🇱🇮","🇱🇹","🇱🇺","🇲🇴","🇲🇬","🇲🇼",
            "🇲🇾","🇲🇻","🇲🇱","🇲🇹","🇲🇭","🇲🇷","🇲🇺","🇲🇽","🇫🇲","🇲🇩",
            "🇲🇨","🇲🇳","🇲🇪","🇲🇦","🇲🇿","🇲🇲","🇳🇦","🇳🇷","🇳🇵","🇳🇱",
            "🇳🇿","🇳🇮","🇳🇪","🇳🇬","🇰🇵","🇲🇰","🇳🇴","🇴🇲","🇵🇰","🇵🇼",
            "🇵🇸","🇵🇦","🇵🇬","🇵🇾","🇵🇪","🇵🇭","🇵🇱","🇵🇹","🇵🇷","🇶🇦",
            "🇷🇴","🇷🇺","🇷🇼","🇼🇸","🇸🇲","🇸🇦","🇸🇳","🇷🇸","🇸🇨","🇸🇱",
            "🇸🇬","🇸🇰","🇸🇮","🇸🇧","🇸🇴","🇿🇦","🇰🇷","🇸🇸","🇪🇸","🇱🇰",
            "🇸🇩","🇸🇷","🇸🇪","🇨🇭","🇸🇾","🇹🇼","🇹🇯","🇹🇿","🇹🇭","🇹🇱",
            "🇹🇬","🇹🇴","🇹🇹","🇹🇳","🇹🇷","🇹🇲","🇹🇻","🇺🇬","🇺🇦","🇦🇪",
            "🇬🇧","🇺🇸","🇺🇾","🇺🇿","🇻🇺","🇻🇪","🇻🇳","🇾🇪","🇿🇲","🇿🇼"
        ]
    )
    
    static func unicodeName(for emoji: String) -> String {
        let mutable = NSMutableString(string: emoji)
        CFStringTransform(mutable, nil, kCFStringTransformToUnicodeName, false)
        return (mutable as String)
            .replacingOccurrences(of: "\\N{", with: " ")
            .replacingOccurrences(of: "}", with: "")
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
    }
    
    private static func searchableText(for emoji: String) -> String {
        let name = unicodeName(for: emoji)
        if let extra = keywords[emoji] {
            return name + " " + extra
        }
        return name
    }
    
    static func search(_ query: String) -> [String] {
        guard !query.isEmpty else { return [] }
        let lowered = query.lowercased()
        var results: [String] = []
        for category in categories {
            for emoji in category.emojis {
                if searchableText(for: emoji).contains(lowered) {
                    results.append(emoji)
                }
            }
        }
        return results
    }
    
    // MARK: - Keyword Aliases
    
    static let keywords: [String: String] = [
        // Smileys
        "😀": "happy grin cheerful",
        "😃": "happy excited joy",
        "😄": "happy laugh joy cheerful",
        "😁": "happy grin teeth",
        "😆": "happy laugh lol",
        "😅": "nervous awkward sweat relief",
        "🤣": "lol rofl dying hilarious",
        "😂": "lol crying laughing tears funny",
        "🙂": "ok fine sure polite",
        "🙃": "sarcasm sarcastic ironic upside",
        "😉": "flirt wink hint",
        "😊": "blush shy sweet cute",
        "😇": "angel innocent good pure",
        "🥰": "love adore hearts crush",
        "😍": "love crush heart eyes",
        "🤩": "wow amazing awesome star struck",
        "😘": "kiss love blowing",
        "😋": "yummy delicious food tasty",
        "😜": "silly playful joke kidding",
        "🤪": "crazy wild silly goofy",
        "🤑": "money rich greedy cash dollar",
        "🤗": "hug warm friendly embrace",
        "🤔": "thinking hmm wonder curious",
        "🤫": "quiet secret shh hush",
        "🤐": "quiet shut zip lips sealed",
        "😴": "sleep tired sleepy zzz bed nap",
        "😷": "sick mask covid ill health",
        "🤒": "sick fever ill temperature",
        "🤕": "hurt injured bandage pain",
        "🤢": "sick nauseous gross disgusted",
        "🤮": "sick vomit puke throw up",
        "🥵": "hot heat sweating warm",
        "🥶": "cold freezing frozen ice",
        "🤯": "mind blown shocked amazed",
        "🥳": "party birthday celebrate woohoo",
        "😎": "cool sunglasses confident chill",
        "🤓": "nerd geek smart study glasses",
        "😕": "confused unsure uncertain",
        "😟": "worried concern nervous",
        "😢": "cry sad tear",
        "😭": "cry sob bawling crying loud sad",
        "😱": "scared scream horror shock omg",
        "😤": "angry huff annoyed frustrated",
        "😡": "angry mad furious rage",
        "😠": "angry mad annoyed",
        "🤬": "swear curse angry expletive",
        "💀": "dead death skull rip",
        "💩": "poop crap turd",
        "👻": "ghost spooky halloween boo",
        "👽": "alien ufo space extraterrestrial",
        "🤖": "robot bot machine ai",
        "👋": "wave hello hi bye goodbye",
        "👍": "yes good ok approve like thumbs up",
        "👎": "no bad dislike thumbs down disapprove",
        "👏": "clap bravo applause congrats",
        "🙏": "please pray thanks grateful hope namaste",
        "💪": "strong muscle power flex gym workout",
        "🧠": "brain smart think intelligent mind",
        
        // Hearts & love
        "❤️": "love heart red",
        "💔": "broken heart sad heartbreak",
        "💕": "love hearts couple",
        "💖": "love sparkle heart",
        "💗": "love growing heart",
        "💘": "love cupid arrow valentine",
        "💝": "love gift heart ribbon",
        
        // Animals
        "🐶": "dog puppy pet woof",
        "🐱": "cat kitten pet meow",
        "🐭": "mouse mice",
        "🐹": "hamster pet",
        "🐰": "rabbit bunny easter",
        "🦊": "fox",
        "🐻": "bear teddy",
        "🐼": "panda",
        "🐨": "koala australia",
        "🐯": "tiger",
        "🦁": "lion king",
        "🐮": "cow moo milk",
        "🐷": "pig oink",
        "🐸": "frog toad ribbit",
        "🐵": "monkey ape",
        "🐔": "chicken hen rooster",
        "🐧": "penguin",
        "🐦": "bird tweet chirp",
        "🦅": "eagle",
        "🦉": "owl night wise",
        "🐴": "horse pony",
        "🦄": "unicorn magic",
        "🐝": "bee honey buzz",
        "🦋": "butterfly",
        "🐢": "turtle slow",
        "🐍": "snake",
        "🐙": "octopus",
        "🐬": "dolphin",
        "🐳": "whale ocean",
        "🦈": "shark jaws",
        "🐘": "elephant",
        "🐾": "paw print pet animal",
        "🔥": "fire hot lit flame trending",
        "🌈": "rainbow pride",
        "⭐": "star favorite",
        "✨": "sparkle magic special glitter",
        "🌊": "wave ocean sea water surf",
        "🌸": "cherry blossom flower spring sakura",
        "🌻": "sunflower flower",
        "🌹": "rose flower red love",
        "🍀": "clover luck lucky irish",
        
        // Food & Drink
        "🍏": "apple green fruit healthy",
        "🍎": "apple red fruit healthy",
        "🍊": "orange tangerine citrus fruit",
        "🍋": "lemon citrus sour fruit",
        "🍌": "banana fruit yellow",
        "🍉": "watermelon fruit summer",
        "🍇": "grapes wine fruit purple",
        "🍓": "strawberry fruit berry",
        "🍒": "cherry fruit",
        "🍑": "peach fruit",
        "🥑": "avocado guacamole healthy",
        "🥦": "broccoli vegetable healthy green",
        "🌽": "corn maize cob",
        "🥕": "carrot vegetable orange",
        "🥔": "potato spud",
        "🍞": "bread loaf bakery",
        "🧀": "cheese",
        "🍳": "egg breakfast frying cooking",
        "🥞": "pancake breakfast stack",
        "🥓": "bacon breakfast meat",
        "🥩": "steak meat beef",
        "🍗": "chicken leg drumstick poultry meat",
        "🍖": "meat bone rib",
        "🌭": "hot dog sausage",
        "🍔": "burger hamburger fast food cheeseburger",
        "🍟": "fries french fries fast food",
        "🍕": "pizza slice italian",
        "🌮": "taco mexican",
        "🌯": "burrito wrap mexican",
        "🍝": "pasta spaghetti italian noodle",
        "🍜": "noodle ramen soup bowl",
        "🍲": "stew soup pot",
        "🍛": "curry rice indian",
        "🍣": "sushi japanese fish",
        "🍱": "bento box japanese lunch",
        "🍤": "shrimp prawn tempura",
        "🍩": "donut doughnut sweet",
        "🍪": "cookie biscuit sweet",
        "🎂": "birthday cake celebration",
        "🍰": "cake dessert slice sweet",
        "🧁": "cupcake muffin sweet",
        "🍦": "ice cream cone dessert sweet",
        "🍫": "chocolate candy bar sweet",
        "🍬": "candy sweet wrapper",
        "🍭": "lollipop candy sweet",
        "🍿": "popcorn movie snack cinema",
        "☕": "coffee cafe latte espresso morning",
        "🍵": "tea matcha green hot",
        "🧃": "juice box drink",
        "🥤": "soda drink cup straw",
        "🧋": "boba bubble tea milk tea",
        "🍺": "beer drink alcohol pub bar",
        "🍻": "beers cheers drink alcohol",
        "🥂": "champagne toast cheers celebrate wine",
        "🍷": "wine glass red drink alcohol",
        "🍸": "cocktail martini drink alcohol",
        "🍹": "tropical drink cocktail",
        "🍾": "champagne bottle celebrate pop",
        
        // Activities & celebrations
        "⚽": "soccer football sport",
        "🏀": "basketball sport",
        "🏈": "football american sport",
        "⚾": "baseball sport",
        "🎾": "tennis sport",
        "🏐": "volleyball sport",
        "🎱": "pool billiards",
        "🏆": "trophy winner champion award",
        "🥇": "gold medal first winner",
        "🥈": "silver medal second",
        "🥉": "bronze medal third",
        "🎯": "target bullseye goal aim",
        "🎮": "game controller gaming video",
        "🧩": "puzzle piece jigsaw",
        "🎨": "art paint palette creative",
        "🎬": "movie film cinema clapper",
        "🎤": "microphone karaoke sing music",
        "🎧": "headphones music listen audio",
        "🎹": "piano keyboard music",
        "🎸": "guitar music rock",
        "🎉": "party celebrate tada congrats",
        "🎊": "confetti party celebrate",
        "🎈": "balloon party birthday",
        "🎁": "gift present box birthday",
        "🎄": "christmas tree holiday xmas",
        "🎃": "pumpkin halloween jack lantern",
        "🪩": "disco ball dance party",
        
        // Travel & places
        "🚗": "car drive vehicle automobile",
        "🚕": "taxi cab ride",
        "🚙": "suv car vehicle",
        "🚌": "bus transit public transport",
        "🏎️": "race car fast speed",
        "🚑": "ambulance emergency hospital",
        "🚒": "fire truck engine emergency",
        "🛻": "pickup truck",
        "🚚": "delivery truck moving",
        "🚲": "bicycle bike cycling ride",
        "🛵": "scooter moped",
        "🏍️": "motorcycle motorbike",
        "✈️": "airplane plane flight travel fly",
        "🚀": "rocket space launch",
        "🛸": "ufo flying saucer alien",
        "🚁": "helicopter chopper",
        "⛵": "sailboat sailing boat",
        "🚤": "speedboat boat",
        "🛳️": "cruise ship boat",
        "🚢": "ship boat",
        "🏠": "house home",
        "🏡": "home garden house",
        "🏢": "office building work",
        "🏥": "hospital clinic medical",
        "🏫": "school education building",
        "🏪": "convenience store shop",
        "🏬": "department store mall shopping",
        "⛪": "church religion",
        "🕌": "mosque religion islam",
        "🏰": "castle kingdom fairy tale",
        "🏖️": "beach vacation holiday sand",
        "🏔️": "mountain snow peak",
        "⛺": "tent camping outdoors",
        "🌅": "sunrise morning",
        "🌄": "sunset evening",
        "🌇": "sunset city evening",
        
        // Objects
        "📱": "phone mobile iphone smartphone cell",
        "💻": "laptop computer macbook work",
        "⌨️": "keyboard type computer",
        "🖥️": "desktop computer monitor screen",
        "📺": "tv television screen",
        "📷": "camera photo picture",
        "📸": "camera flash photo selfie",
        "🎥": "camera movie film video",
        "📞": "phone telephone call",
        "⏰": "alarm clock time wake up morning",
        "⌚": "watch time",
        "💡": "idea light bulb bright",
        "🔋": "battery power charge",
        "💰": "money bag cash dollar rich",
        "💵": "dollar money cash bill",
        "💳": "credit card payment debit",
        "💎": "diamond gem jewel precious",
        "🔑": "key lock unlock password",
        "🔒": "lock secure private",
        "🔓": "unlock open",
        "🔨": "hammer tool build",
        "🔧": "wrench tool fix repair",
        "⚙️": "gear settings config",
        "🔫": "gun weapon pistol",
        "💣": "bomb explosive",
        "🔪": "knife blade cut",
        "💊": "pill medicine drug health",
        "💉": "syringe vaccine injection shot needle",
        "🩺": "stethoscope doctor medical health",
        "🚪": "door entrance exit",
        "🛏️": "bed sleep bedroom",
        "🛋️": "couch sofa living room furniture",
        "🪑": "chair seat sit furniture",
        "🚽": "toilet bathroom restroom",
        "🛁": "bath bathtub shower",
        "🛒": "shopping cart trolley grocery store supermarket",
        "📝": "note memo write pencil paper",
        "📋": "clipboard checklist list",
        "📅": "calendar date schedule",
        "📎": "paperclip attachment",
        "✂️": "scissors cut",
        "📦": "package box delivery parcel",
        "✉️": "email mail letter envelope",
        "📮": "mailbox post letter",
        "📧": "email mail",
        "💼": "briefcase work business office",
        "📁": "folder file directory",
        "🗑️": "trash delete garbage bin recycle",
        "🧾": "receipt bill invoice",
        
        // Symbols
        "💯": "hundred perfect score",
        "✅": "check done yes complete",
        "❌": "no wrong cross cancel delete",
        "⚠️": "warning caution alert",
        "🚫": "no prohibited forbidden banned stop",
        "♻️": "recycle green environment",
        "💤": "sleep zzz tired nap",
        "🔍": "search find look magnifying glass",
        
        // Flags
        "🇺🇸": "usa united states america",
        "🇬🇧": "uk united kingdom britain england",
        "🇨🇦": "canada",
        "🇦🇺": "australia",
        "🇩🇪": "germany deutsch",
        "🇫🇷": "france french",
        "🇮🇹": "italy italian",
        "🇪🇸": "spain spanish",
        "🇯🇵": "japan japanese",
        "🇰🇷": "korea korean south",
        "🇨🇳": "china chinese",
        "🇮🇳": "india indian",
        "🇧🇷": "brazil brazilian",
        "🇲🇽": "mexico mexican",
        "🇷🇺": "russia russian",
    ]
}

// MARK: - Emoji Picker Sheet

struct EmojiPickerSheet: View {
    @Binding var selectedEmoji: String
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var activeCategory: String = EmojiStore.categories.first?.id ?? ""
    @State private var searchResults: [String] = []
    @State private var isSearching = false
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    
    var body: some View {
        VStack(spacing: 0) {
            categoryBar
                .fixedSize(horizontal: false, vertical: true)
            
            Group {
                if isSearching && !searchText.isEmpty {
                    searchResultsGrid
                } else {
                    emojiGrid
                }
            }
            .frame(maxHeight: .infinity)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.1),
                        .init(color: .black, location: 0.8),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            
            searchBar
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 320, height: 360)
    }
    
    // MARK: - Category Bar
    
    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(EmojiStore.categories) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeCategory = category.id
                            isSearching = false
                            searchText = ""
                        }
                    } label: {
                        Image(systemName: category.symbol)
                            .font(.system(size: 16))
                            .foregroundStyle(activeCategory == category.id && !isSearching ? .text : .text.opacity(0.6))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(category.name)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Emoji Grid
    
    private var emojiGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(EmojiStore.categories) { category in
                        Section {
                            ForEach(category.emojis, id: \.self) { emoji in
                                emojiButton(emoji)
                            }
                        } header: {
                            Text(category.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 16)
                                .padding(.bottom, 4)
                                .id(category.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: activeCategory) { _, newValue in
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .top)
                }
            }
        }
    }
    
    // MARK: - Search Results Grid
    
    private var searchResultsGrid: some View {
        ScrollView {
            if searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(searchResults, id: \.self) { emoji in
                        emojiButton(emoji)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
    
    // MARK: - Emoji Button
    
    private func emojiButton(_ emoji: String) -> some View {
        Button {
            selectedEmoji = emoji
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        } label: {
            Text(emoji)
                .font(.system(size: 30))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(EmojiStore.unicodeName(for: emoji))
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            
            TextField("Search emoji", text: $searchText)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchText) { _, newValue in
                    isSearching = !newValue.isEmpty
                    if newValue.isEmpty {
                        searchResults = []
                    } else {
                        Task.detached(priority: .userInitiated) {
                            let results = EmojiStore.search(newValue)
                            await MainActor.run {
                                searchResults = results
                            }
                        }
                    }
                }
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    isSearching = false
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.background.secondary)
        .clipShape(Capsule())
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Preview

#Preview("Emoji Picker") {
    struct PreviewWrapper: View {
        @State private var emoji = "🍕"
        @State private var showPicker = true
        
        var body: some View {
            VStack(alignment: .leading) {
                Text("Selected: \(emoji)")
                    .font(.largeTitle)
                    .frame(maxWidth: .infinity)
                Button("Pick Emoji") { showPicker = true }
                    .popover(isPresented: $showPicker, arrowEdge: .leading) {
                        EmojiPickerSheet(selectedEmoji: $emoji)
                            .presentationCompactAdaptation(.popover)
                    }
            }
            .frame(maxWidth: .infinity)
        }
    }
    return PreviewWrapper()
}
