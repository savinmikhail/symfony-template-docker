<?php

declare(strict_types=1);

namespace App\Shared\Console;

use Symfony\Component\Console\Output\ConsoleOutput;
use Symfony\Component\DependencyInjection\Attribute\Exclude;

#[Exclude]
final class JsonConsoleOutput extends ConsoleOutput
{
    public function __construct(int $verbosity = self::VERBOSITY_NORMAL)
    {
        parent::__construct(verbosity: $verbosity, decorated: false);
        $this->setErrorOutput(error: new JsonStreamOutput(stream: fopen(filename: 'php://stderr', mode: 'w'), verbosity: $verbosity, decorated: false));
    }

    protected function doWrite(string $message, bool $newline): void
    {
        if ('' !== trim(string: $message)) {
            parent::doWrite(message: JsonStreamOutput::encode(message: $message, levelName: 'INFO'), newline: true);
        }
    }
}
