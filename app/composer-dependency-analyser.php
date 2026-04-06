<?php

declare(strict_types=1);

use ShipMonk\ComposerDependencyAnalyser\Config\Configuration;
use ShipMonk\ComposerDependencyAnalyser\Config\ErrorType;

require_once __DIR__ . '/vendor/autoload.php';

$config = new Configuration();

$config
    ->addPathToScan(__DIR__ . '/bin', isDev: false)
    ->addPathToScan(__DIR__ . '/config', isDev: false)
    ->addPathToScan(__DIR__ . '/public', isDev: false)
    ->addPathToScan(__DIR__ . '/tests', isDev: true)
    ->addPathToExclude(__DIR__ . '/tests/Architecture')
    ->addForceUsedSymbols(extractConfigSymbols([
        __DIR__ . '/config/bundles.php',
        __DIR__ . '/config/routes.yaml',
        __DIR__ . '/config/packages/doctrine.yaml',
        __DIR__ . '/config/packages/messenger.yaml',
        __DIR__ . '/phpstan.neon.dist',
    ]))
    ->ignoreErrorsOnPackage('symfony/flex', [ErrorType::UNUSED_DEPENDENCY])
    ->ignoreErrorsOnPackage('symfony/cache', [ErrorType::UNUSED_DEPENDENCY])
    ->ignoreErrorsOnPackage('symfony/amqp-messenger', [ErrorType::UNUSED_DEPENDENCY])
    ->ignoreErrorsOnPackage('symfony/doctrine-messenger', [ErrorType::UNUSED_DEPENDENCY])
    ->ignoreErrorsOnPackage('symfony/console', [ErrorType::UNUSED_DEPENDENCY])
    ->ignoreErrorsOnPackage('symfony/validator', [ErrorType::UNUSED_DEPENDENCY])
    ->ignoreErrorsOnPackage('symfony/yaml', [ErrorType::UNUSED_DEPENDENCY])
    ->ignoreErrorsOnPackage('symfony/dotenv', [ErrorType::PROD_DEPENDENCY_ONLY_IN_DEV])
    ->ignoreErrorsOnPackage('symfony/runtime', [ErrorType::UNUSED_DEPENDENCY])
    ->ignoreErrorsOnExtension('ext-ctype', [ErrorType::UNUSED_DEPENDENCY])
    ->ignoreErrorsOnExtension('ext-iconv', [ErrorType::UNUSED_DEPENDENCY]);

return $config;

/**
 * @param list<string> $paths
 * @return list<string>
 */
function extractConfigSymbols(array $paths): array
{
    $classNameRegex = '[a-zA-Z_\x80-\xff][a-zA-Z0-9_\x80-\xff]*';
    $fqcnRegex = "~$classNameRegex(?:\\\\$classNameRegex)+~";
    $symbols = [];

    foreach ($paths as $path) {
        $contents = file_get_contents($path);
        if ($contents === false) {
            continue;
        }

        preg_match_all($fqcnRegex, $contents, $matches);

        foreach ($matches[0] as $symbol) {
            if (
                class_exists($symbol)
                || interface_exists($symbol)
                || trait_exists($symbol)
                || (function_exists('enum_exists') && enum_exists($symbol))
            ) {
                $symbols[$symbol] = $symbol;
            }
        }
    }

    return array_values($symbols);
}
