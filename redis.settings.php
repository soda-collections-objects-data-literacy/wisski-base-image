<?php

/**
 * Redis cache backend configuration for WissKI.
 *
 * Based on official documentation: https://project.pages.drupalcode.org/redis/
 *
 * This file configures Drupal to use Redis for caching when available.
 * The Redis module must be installed via Composer.
 */

// Only configure Redis if the extension is loaded and connection is available.
if (extension_loaded('redis')) {
  // Redis connection settings from environment variables.
  $redisHost = getenv('REDIS_HOST') ?: 'redis';
  $redisPort = getenv('REDIS_PORT') ?: 6379;

  // Test Redis connection before configuring.
  try {
    $redis = new Redis();
    if (@$redis->connect($redisHost, $redisPort, 2)) {
      $redis->close();

      // Configure Redis connection.
      // https://project.pages.drupalcode.org/redis/#common-configuration
      $settings['redis.connection']['interface'] = 'PhpRedis';
      $settings['redis.connection']['host'] = $redisHost;
      $settings['redis.connection']['port'] = $redisPort;

      // Use persistent connections for better performance.
      // https://project.pages.drupalcode.org/redis/#use-persistent-connections
      $settings['redis.connection']['persistent'] = TRUE;

      // Optional: Set a prefix for cache keys (recommended for multi-site).
      // https://project.pages.drupalcode.org/redis/#prefixing-site-cache-entries-avoiding-sites-name-collision
      // $settings['cache_prefix']['default'] = 'wisski_';

      // Only configure cache backends if Redis module services are available.
      // This prevents errors during installation before the module is enabled.
      if (file_exists('modules/contrib/redis/redis.services.yml')) {
        // Set Redis as the default cache backend.
        $settings['cache']['default'] = 'cache.backend.redis';

        // Keep the database cache for the Form cache bin (required for Drupal).
        $settings['cache']['bins']['form'] = 'cache.backend.database';

        // Use Redis for additional bins for better performance.
        $settings['cache']['bins']['bootstrap'] = 'cache.backend.redis';
        $settings['cache']['bins']['render'] = 'cache.backend.redis';
        $settings['cache']['bins']['data'] = 'cache.backend.redis';
        $settings['cache']['bins']['discovery'] = 'cache.backend.redis';
      }

      // Enable compression to reduce Redis memory usage.
      // https://project.pages.drupalcode.org/redis/#common-configuration
      // Compress data larger than 100 bytes with level 1 (fast, good compression).
      $settings['redis_compress_length'] = 100;
      $settings['redis_compress_level'] = 1;

      // TTL offset: Allow expired items to be fetched for 1 hour.
      // https://project.pages.drupalcode.org/redis/#expiration-of-cache-items
      $settings['redis_ttl_offset'] = 3600;

      // Cache optimizations.
      // https://project.pages.drupalcode.org/redis/#cache-optimizations
      // Treat invalidateAll() same as deleteAll() (recommended for performance).
      $settings['redis_invalidate_all_as_delete'] = TRUE;

      // Include Redis services for lock backend, flood control, etc.
      // https://project.pages.drupalcode.org/redis/#common-configuration
      if (file_exists('modules/contrib/redis/redis.services.yml')) {
        $settings['container_yamls'][] = 'modules/contrib/redis/redis.services.yml';
      }

      // Include example services (lock, flood, queue backends).
      if (file_exists('modules/contrib/redis/example.services.yml')) {
        $settings['container_yamls'][] = 'modules/contrib/redis/example.services.yml';
      }

      // Configure bootstrap container to use Redis (improves performance).
      // https://project.pages.drupalcode.org/redis/#common-configuration
      // Note: Only configure if Redis module is installed and classes are available.
      if (file_exists($app_root . '/modules/contrib/redis/src')) {
        // Manually add the classloader path for Redis module.
        $class_loader->addPsr4('Drupal\\redis\\', 'modules/contrib/redis/src');

        // Only enable bootstrap container if class is available.
        if (class_exists('Drupal\redis\ClientFactory')) {
          $settings['bootstrap_container_definition'] = [
            'parameters' => [],
            'services' => [
              'redis.factory' => [
                'class' => 'Drupal\redis\ClientFactory',
              ],
              'cache.backend.redis' => [
                'class' => 'Drupal\redis\Cache\CacheBackendFactory',
                'arguments' => ['@redis.factory', '@cache_tags_provider.container', '@serialization.phpserialize'],
              ],
              'cache.container' => [
                'class' => '\Drupal\redis\Cache\PhpRedis',
                'factory' => ['@cache.backend.redis', 'get'],
                'arguments' => ['container'],
              ],
              'cache_tags_provider.container' => [
                'class' => 'Drupal\redis\Cache\RedisCacheTagsChecksum',
                'arguments' => ['@redis.factory'],
              ],
              'serialization.phpserialize' => [
                'class' => 'Drupal\Component\Serialization\PhpSerialize',
              ],
            ],
          ];
        }
      }

    }
  } catch (Exception $e) {
    // Redis connection failed, continue without Redis caching.
    error_log('Redis connection failed: ' . $e->getMessage());
  }
}
