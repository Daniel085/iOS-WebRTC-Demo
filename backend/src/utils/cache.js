/**
 * Cache Utility
 * Simple in-memory cache for development
 * In production, replace with Redis
 */

const logger = require('./logger');

class SimpleCache {
  constructor() {
    this.cache = new Map();
    this.ttls = new Map();
  }

  /**
   * Set a value in cache with optional TTL
   * @param {string} key
   * @param {any} value
   * @param {number} ttl - Time to live in seconds
   */
  async set(key, value, ttl = null) {
    this.cache.set(key, value);

    if (ttl) {
      const expiresAt = Date.now() + ttl * 1000;
      this.ttls.set(key, expiresAt);

      // Auto-delete after TTL
      setTimeout(() => {
        this.del(key);
      }, ttl * 1000);
    }

    logger.debug(`Cache SET: ${key}`);
    return true;
  }

  /**
   * Get a value from cache
   * @param {string} key
   */
  async get(key) {
    // Check if expired
    if (this.ttls.has(key)) {
      const expiresAt = this.ttls.get(key);
      if (Date.now() > expiresAt) {
        this.del(key);
        return null;
      }
    }

    const value = this.cache.get(key);
    logger.debug(`Cache GET: ${key} - ${value !== undefined ? 'HIT' : 'MISS'}`);
    return value;
  }

  /**
   * Delete a value from cache
   * @param {string} key
   */
  async del(key) {
    this.cache.delete(key);
    this.ttls.delete(key);
    logger.debug(`Cache DEL: ${key}`);
    return true;
  }

  /**
   * Check if key exists
   * @param {string} key
   */
  async has(key) {
    // Check if expired
    if (this.ttls.has(key)) {
      const expiresAt = this.ttls.get(key);
      if (Date.now() > expiresAt) {
        this.del(key);
        return false;
      }
    }

    return this.cache.has(key);
  }

  /**
   * Clear all cache
   */
  async clear() {
    this.cache.clear();
    this.ttls.clear();
    logger.debug('Cache cleared');
    return true;
  }

  /**
   * Get cache size
   */
  size() {
    return this.cache.size;
  }
}

// For production, use Redis
class RedisCache {
  constructor() {
    const redis = require('redis');
    this.client = redis.createClient({
      host: process.env.REDIS_HOST || 'localhost',
      port: process.env.REDIS_PORT || 6379,
      password: process.env.REDIS_PASSWORD
    });

    this.client.on('error', (err) => {
      logger.error('Redis error:', err);
    });

    this.client.on('connect', () => {
      logger.info('Connected to Redis');
    });
  }

  async set(key, value, ttl = null) {
    const stringValue = JSON.stringify(value);
    if (ttl) {
      await this.client.setex(key, ttl, stringValue);
    } else {
      await this.client.set(key, stringValue);
    }
    return true;
  }

  async get(key) {
    const value = await this.client.get(key);
    return value ? JSON.parse(value) : null;
  }

  async del(key) {
    await this.client.del(key);
    return true;
  }

  async has(key) {
    const exists = await this.client.exists(key);
    return exists === 1;
  }

  async clear() {
    await this.client.flushdb();
    return true;
  }
}

// Export appropriate cache based on environment
const cache = process.env.USE_REDIS === 'true' ? new RedisCache() : new SimpleCache();

module.exports = cache;
