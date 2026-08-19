<?php

declare(strict_types=1);

use Symfony\Component\Dotenv\Dotenv;

require dirname(path: __DIR__).'/vendor/autoload.php';

(new Dotenv())->bootEnv(path: dirname(path: __DIR__).'/.env');

if ($_SERVER['APP_DEBUG']) {
    umask(mask: 0000);
}
