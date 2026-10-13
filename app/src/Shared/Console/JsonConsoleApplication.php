<?php

declare(strict_types=1);

namespace App\Shared\Console;

use Symfony\Bundle\FrameworkBundle\Console\Application;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\ConsoleOutput;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\DependencyInjection\Attribute\Exclude;

/** JSON is opt-in for background workers; interactive/data-export commands keep their output. */
#[Exclude]
final class JsonConsoleApplication extends Application
{
    public function run(?InputInterface $input = null, ?OutputInterface $output = null): int
    {
        if ('json' === getenv('APP_LOG_FORMAT') && (!$output instanceof OutputInterface || $output instanceof ConsoleOutput)) {
            $output = new JsonConsoleOutput(verbosity: $output?->getVerbosity() ?? OutputInterface::VERBOSITY_NORMAL);
        }

        return parent::run(input: $input, output: $output);
    }

    public function doRun(InputInterface $input, OutputInterface $output): int
    {
        $exitCode = parent::doRun(input: $input, output: $output);
        if (0 !== $exitCode && $output instanceof JsonConsoleOutput) {
            $output->getErrorOutput()->writeln(sprintf('Command %s exited with status %d.', $input->getFirstArgument() ?? 'unknown', $exitCode));
        }

        return $exitCode;
    }
}
