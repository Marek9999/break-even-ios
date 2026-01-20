import { v } from "convex/values";
import { action, internalMutation, internalQuery, query } from "./_generated/server";
import { internal } from "./_generated/api";

/**
 * Supported currencies in the app
 */
export const SUPPORTED_CURRENCIES = ["USD", "EUR", "GBP", "CAD", "AUD", "INR", "JPY"] as const;
export type SupportedCurrency = (typeof SUPPORTED_CURRENCIES)[number];

/**
 * Cache TTL: 24 hours in milliseconds
 */
const CACHE_TTL_MS = 24 * 60 * 60 * 1000;

/**
 * Exchange rates structure
 */
export interface ExchangeRates {
  baseCurrency: string;
  rates: {
    USD: number;
    EUR: number;
    GBP: number;
    CAD: number;
    AUD: number;
    INR: number;
    JPY: number;
  };
  fetchedAt: number;
}

/**
 * Get the latest cached exchange rates
 * Returns null if no cached rates exist
 */
export const getLatestRates = query({
  args: {},
  handler: async (ctx): Promise<ExchangeRates | null> => {
    const latestRates = await ctx.db
      .query("exchangeRates")
      .withIndex("by_base_fetchedAt", (q) => q.eq("baseCurrency", "USD"))
      .order("desc")
      .first();

    if (!latestRates) {
      return null;
    }

    return {
      baseCurrency: latestRates.baseCurrency,
      rates: latestRates.rates,
      fetchedAt: latestRates.fetchedAt,
    };
  },
});

/**
 * Internal query to get latest rates (for use within actions)
 */
export const internalGetLatestRates = internalQuery({
  args: {},
  handler: async (ctx): Promise<ExchangeRates | null> => {
    const latestRates = await ctx.db
      .query("exchangeRates")
      .withIndex("by_base_fetchedAt", (q) => q.eq("baseCurrency", "USD"))
      .order("desc")
      .first();

    if (!latestRates) {
      return null;
    }

    return {
      baseCurrency: latestRates.baseCurrency,
      rates: latestRates.rates,
      fetchedAt: latestRates.fetchedAt,
    };
  },
});

/**
 * Internal mutation to store fetched rates
 */
export const storeExchangeRates = internalMutation({
  args: {
    baseCurrency: v.string(),
    rates: v.object({
      USD: v.float64(),
      EUR: v.float64(),
      GBP: v.float64(),
      CAD: v.float64(),
      AUD: v.float64(),
      INR: v.float64(),
      JPY: v.float64(),
    }),
    fetchedAt: v.number(),
  },
  handler: async (ctx, args) => {
    await ctx.db.insert("exchangeRates", {
      baseCurrency: args.baseCurrency,
      rates: args.rates,
      fetchedAt: args.fetchedAt,
    });
  },
});

/**
 * Action to fetch exchange rates from ExchangeRate-API
 * Only called when creating a split AND cached rates are stale (>24h)
 * 
 * Returns the exchange rates (either fresh from API or from cache)
 */
export const getOrFetchExchangeRates = action({
  args: {},
  handler: async (ctx): Promise<ExchangeRates> => {
    // First, check if we have fresh cached rates
    const cachedRates = await ctx.runQuery(internal.currency.internalGetLatestRates);
    
    const now = Date.now();
    
    // If cache exists and is fresh (< 24 hours old), return it
    if (cachedRates && (now - cachedRates.fetchedAt) < CACHE_TTL_MS) {
      console.log("Using cached exchange rates (age: " + Math.round((now - cachedRates.fetchedAt) / 1000 / 60) + " minutes)");
      return cachedRates;
    }

    // Cache is stale or doesn't exist - fetch from API
    console.log("Fetching fresh exchange rates from API...");
    
    // Get API key from environment variable
    const apiKey = process.env.EXCHANGERATE_API_KEY;
    
    if (!apiKey) {
      console.warn("EXCHANGERATE_API_KEY not set - using fallback rates");
      // Return fallback rates if no API key (for development)
      const fallbackRates: ExchangeRates = {
        baseCurrency: "USD",
        rates: {
          USD: 1.0,
          EUR: 0.92,
          GBP: 0.79,
          CAD: 1.36,
          AUD: 1.53,
          INR: 83.12,
          JPY: 149.50,
        },
        fetchedAt: now,
      };
      
      // Store fallback rates in cache
      await ctx.runMutation(internal.currency.storeExchangeRates, fallbackRates);
      return fallbackRates;
    }

    try {
      const response = await fetch(
        `https://v6.exchangerate-api.com/v6/${apiKey}/latest/USD`
      );

      if (!response.ok) {
        throw new Error(`API responded with status: ${response.status}`);
      }

      const data = await response.json();

      if (data.result !== "success") {
        throw new Error(`API error: ${data["error-type"]}`);
      }

      // Extract only the currencies we support
      const rates: ExchangeRates["rates"] = {
        USD: 1.0,
        EUR: data.conversion_rates.EUR || 0.92,
        GBP: data.conversion_rates.GBP || 0.79,
        CAD: data.conversion_rates.CAD || 1.36,
        AUD: data.conversion_rates.AUD || 1.53,
        INR: data.conversion_rates.INR || 83.12,
        JPY: data.conversion_rates.JPY || 149.50,
      };

      const freshRates: ExchangeRates = {
        baseCurrency: "USD",
        rates,
        fetchedAt: now,
      };

      // Store in cache
      await ctx.runMutation(internal.currency.storeExchangeRates, freshRates);
      
      console.log("Fresh exchange rates fetched and cached");
      return freshRates;
    } catch (error) {
      console.error("Failed to fetch exchange rates:", error);
      
      // If we have cached rates (even if stale), use them as fallback
      if (cachedRates) {
        console.log("Using stale cached rates as fallback");
        return cachedRates;
      }
      
      // Last resort: use hardcoded fallback rates
      const fallbackRates: ExchangeRates = {
        baseCurrency: "USD",
        rates: {
          USD: 1.0,
          EUR: 0.92,
          GBP: 0.79,
          CAD: 1.36,
          AUD: 1.53,
          INR: 83.12,
          JPY: 149.50,
        },
        fetchedAt: now,
      };
      
      await ctx.runMutation(internal.currency.storeExchangeRates, fallbackRates);
      return fallbackRates;
    }
  },
});

/**
 * Convert an amount from one currency to another using given exchange rates
 * All rates are relative to USD, so we convert: fromCurrency -> USD -> toCurrency
 * 
 * @param amount - The amount to convert
 * @param fromCurrency - Source currency code
 * @param toCurrency - Target currency code
 * @param rates - Exchange rates object (rates relative to USD)
 * @returns Converted amount
 */
export function convertAmount(
  amount: number,
  fromCurrency: string,
  toCurrency: string,
  rates: ExchangeRates["rates"]
): number {
  if (fromCurrency === toCurrency) {
    return amount;
  }

  const fromRate = rates[fromCurrency as SupportedCurrency];
  const toRate = rates[toCurrency as SupportedCurrency];

  if (!fromRate || !toRate) {
    console.warn(`Unknown currency: ${fromCurrency} or ${toCurrency}`);
    return amount;
  }

  // Convert: amount in fromCurrency -> USD -> toCurrency
  // If 1 USD = X fromCurrency, then amount/X = amount in USD
  // If 1 USD = Y toCurrency, then (amount/X) * Y = amount in toCurrency
  const amountInUSD = amount / fromRate;
  const convertedAmount = amountInUSD * toRate;

  return convertedAmount;
}

/**
 * Get currency symbol for a currency code
 */
export function getCurrencySymbol(currencyCode: string): string {
  const symbols: Record<string, string> = {
    USD: "$",
    EUR: "€",
    GBP: "£",
    CAD: "C$",
    AUD: "A$",
    INR: "₹",
    JPY: "¥",
  };
  return symbols[currencyCode] || currencyCode;
}

/**
 * Get currency display name
 */
export function getCurrencyName(currencyCode: string): string {
  const names: Record<string, string> = {
    USD: "US Dollar",
    EUR: "Euro",
    GBP: "British Pound",
    CAD: "Canadian Dollar",
    AUD: "Australian Dollar",
    INR: "Indian Rupee",
    JPY: "Japanese Yen",
  };
  return names[currencyCode] || currencyCode;
}
