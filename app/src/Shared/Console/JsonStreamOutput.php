<?php

declare(strict_types=1);

namespace App\Shared\Console;

use Symfony\Component\Console\Output\StreamOutput;
use Symfony\Component\DependencyInjection\Attribute\Exclude;

#[Exclude]
final class JsonStreamOutput extends StreamOutput
{
    public static function encode(string $message, string $levelName): string
    {
        // Monolog records already carry their own severity and context.
        $record = json_decode(json: $message, associative: true);
        if (is_array(value: $record) && isset($record['level_name'])) {
            return rtrim(string: $message, characters: "\r\n");
        }

        return json_encode(value: [
            'message' => $message,
            'level_name' => $levelName,
            'channel' => 'console',
            'datetime' => gmdate(format: 'c'),
        ], flags: JSON_THROW_ON_ERROR | JSON_INVALID_UTF8_SUBSTITUTE | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }

    protected function doWrite(string $message, bool $newline): void
    {
        if ('' !== trim(string: $message)) {
            parent::doWrite(message: self::encode(message: $message, levelName: 'ERROR'), newline: true);
        }
    }
}
