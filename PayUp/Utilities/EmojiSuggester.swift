//
//  EmojiSuggester.swift
//  PayUp
//
//  Picks a sensible emoji for a split based on its title.
//
//  Strategy: lowercase + word-tokenize the title, then walk an ordered list of
//  keyword groups and return the first emoji whose group contains any of the
//  title's tokens. Order matters – put more specific brand/category keywords
//  before the generic catch-alls.
//

import Foundation

enum EmojiSuggester {

    /// Returns a suggested emoji for the given title, or `nil` if nothing
    /// confidently matches. Caller decides what to do on `nil` (typically:
    /// leave the emoji empty so the placeholder shows).
    static func suggest(for title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let tokens = Set(
            trimmed
                .lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )
        guard !tokens.isEmpty else { return nil }

        for (keywords, emoji) in mappings {
            if keywords.contains(where: { tokens.contains($0) }) {
                return emoji
            }
        }
        return nil
    }

    // MARK: - Keyword Map
    //
    // Ordered: brand names and specific cuisines first, broader categories
    // last so a "starbucks coffee" title matches ☕ via "starbucks" and a bare
    // "coffee" still works via the later generic entry. Plurals are listed
    // explicitly because matching is exact-word, not stem-based.
    //
    private static let mappings: [(keywords: [String], emoji: String)] = [
        // --- Specific brands / chains ---
        (["mcdonalds", "mcdonald", "wendys", "burgerking", "shake", "shack", "fiveguys"], "🍔"),
        (["starbucks", "dunkin", "nespresso", "blue", "bottle"], "☕"),
        (["chipotle", "qdoba", "tacobell"], "🌮"),
        (["dominos", "papajohns", "pizzahut"], "🍕"),
        (["kfc", "popeyes", "chickfila"], "🍗"),
        (["uber", "lyft", "ola"], "🚕"),
        (["doordash", "ubereats", "grubhub", "postmates", "delivery"], "🛵"),
        (["amazon", "ebay", "etsy"], "📦"),
        (["target", "walmart", "costco", "ikea"], "🛍️"),
        (["wholefoods", "trader", "joes", "safeway", "kroger", "aldi"], "🛒"),
        (["cvs", "walgreens", "pharmacy"], "💊"),
        (["netflix", "spotify", "hulu", "disney", "youtube", "apple", "music"], "📺"),
        (["airbnb", "marriott", "hilton", "hyatt", "hotel", "motel", "resort", "lodging"], "🏨"),
        (["delta", "united", "lufthansa", "emirates", "airline", "airlines", "flight", "airfare", "plane"], "✈️"),
        (["amtrak", "metro", "subway", "train", "rail"], "🚆"),
        (["shell", "chevron", "bp", "exxon", "gas", "fuel", "petrol"], "⛽"),
        (["amc", "regal", "imax", "cinema", "movie", "movies", "theatre", "theater"], "🎬"),
        (["xbox", "playstation", "nintendo", "steam", "gaming"], "🎮"),
        (["verizon", "att", "tmobile", "mobile", "wireless"], "📱"),
        (["comcast", "xfinity", "wifi", "internet", "broadband"], "📶"),

        // --- Food: cuisine + specific dishes ---
        (["pizza", "pizzas"], "🍕"),
        (["sushi", "sashimi", "japanese", "ramen", "udon"], "🍣"),
        (["taco", "tacos", "burrito", "burritos", "mexican", "quesadilla"], "🌮"),
        (["noodle", "noodles", "pho", "chowmein"], "🍜"),
        (["chinese", "dimsum"], "🥡"),
        (["indian", "curry", "biryani", "tandoori", "naan"], "🍛"),
        (["thai", "pad"], "🥡"),
        (["bbq", "barbecue", "barbeque", "grill", "grilled", "steak", "steakhouse"], "🥩"),
        (["burger", "burgers", "cheeseburger", "hamburger"], "🍔"),
        (["chicken", "wings", "nugget", "nuggets", "fried"], "🍗"),
        (["fries", "kebab", "kebabs", "shawarma"], "🍟"),
        (["sandwich", "sandwiches", "sub", "subs", "deli", "panini"], "🥪"),
        (["bread", "bakery", "baguette", "croissant", "pastry", "pastries"], "🥖"),
        (["donut", "donuts", "doughnut", "doughnuts"], "🍩"),
        (["icecream", "icrm", "gelato", "frozen", "yogurt", "froyo"], "🍦"),
        (["cake", "cupcake", "cupcakes", "dessert", "desserts", "tiramisu", "mochi"], "🍰"),
        (["chocolate", "candy", "sweets"], "🍫"),
        (["coffee", "espresso", "latte", "cappuccino", "mocha", "cafe", "café"], "☕"),
        (["tea", "matcha", "boba", "bubble"], "🧋"),
        (["juice", "smoothie", "smoothies"], "🧃"),
        (["beer", "beers", "pub", "brewery", "ale", "lager"], "🍺"),
        (["wine", "vineyard", "winery"], "🍷"),
        (["cocktail", "cocktails", "drinks", "bar", "bars", "martini"], "🍸"),
        (["champagne", "prosecco", "bubbly"], "🍾"),

        // --- Meals (most generic last among food) ---
        (["breakfast", "brunch"], "🥞"),
        (["lunch", "dinner", "supper", "meal", "meals", "restaurant", "restaurants",
          "diner", "bistro", "eatery", "kitchen", "food", "feast"], "🍽️"),
        (["snack", "snacks"], "🍿"),
        (["popcorn"], "🍿"),
        (["picnic"], "🧺"),

        // --- Groceries / shopping ---
        (["grocery", "groceries", "supermarket", "market", "produce"], "🛒"),
        (["clothes", "clothing", "outfit", "shirt", "shoes", "shopping", "mall"], "🛍️"),
        (["book", "books", "bookstore"], "📚"),

        // --- Transport ---
        (["taxi", "cab", "ride", "rideshare"], "🚕"),
        (["bus"], "🚌"),
        (["bike", "bicycle", "cycling", "scooter"], "🚲"),
        (["car", "auto", "rental", "uhaul"], "🚗"),
        (["parking"], "🅿️"),
        (["toll", "tolls"], "🛣️"),
        (["boat", "ferry", "cruise", "sailing"], "🚢"),

        // --- Stays / housing / utilities ---
        (["rent"], "🏠"),
        (["mortgage", "loan", "bank", "banking"], "🏦"),
        (["electric", "electricity", "power", "utilities", "utility"], "💡"),
        (["water"], "💧"),
        (["heat", "heating", "gas"], "🔥"),
        (["trash", "garbage"], "🗑️"),
        (["cleaning", "cleaner", "laundry"], "🧺"),

        // --- Health / fitness ---
        (["gym", "fitness", "workout", "yoga", "pilates"], "🏋️"),
        (["doctor", "clinic", "medical", "hospital", "dentist", "dental"], "🩺"),
        (["medicine", "meds", "prescription"], "💊"),

        // --- Entertainment / events ---
        (["concert", "festival", "show"], "🎤"),
        (["sports", "soccer", "football", "basketball", "baseball", "tennis", "match"], "⚽"),
        (["museum", "gallery", "exhibit"], "🖼️"),
        (["zoo", "aquarium"], "🐾"),
        (["club", "clubbing", "nightclub", "disco"], "🪩"),

        // --- Celebrations / gifts ---
        (["birthday", "bday"], "🎂"),
        (["gift", "gifts", "present", "presents"], "🎁"),
        (["party", "parties", "celebration"], "🎉"),
        (["wedding", "anniversary"], "💍"),
        (["holiday", "vacation", "trip", "travel", "getaway"], "🏖️"),
        (["beach"], "🏖️"),
        (["camping", "camp", "tent"], "⛺"),
        (["hiking", "hike"], "🥾"),
        (["ski", "skiing", "snow", "snowboard"], "🎿"),

        // --- Pets ---
        (["pet", "pets", "dog", "dogs", "cat", "cats", "vet"], "🐾"),

        // --- Education / work ---
        (["school", "tuition", "class", "course", "university", "college"], "🎓"),
        (["office", "work", "coworking"], "💼"),

        // --- Misc ---
        (["receipt"], "🧾"),
        (["tax", "taxes"], "🧾"),
        (["donation", "charity"], "💝")
    ]
}
