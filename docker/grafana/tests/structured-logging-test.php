<?php

declare(strict_types=1);

$root = dirname(__DIR__, 3);
require $argv[1] ?? $root.'/app/vendor/autoload.php';
foreach (['JsonStreamOutput', 'JsonConsoleOutput', 'JsonConsoleApplication'] as $class) {
    require_once $root.'/app/src/Shared/Console/'.$class.'.php';
}

if (isset($argv[2])) {
    $kernel = new class ('test', false) extends Symfony\Component\HttpKernel\Kernel {
        public function registerBundles(): iterable
        {
            return [];
        }
        public function registerContainerConfiguration(Symfony\Component\Config\Loader\LoaderInterface $loader): void
        {
        }
        public function boot(): void
        {
            $this->container = new Symfony\Component\DependencyInjection\ContainerBuilder();
            $this->container->set('event_dispatcher', new Symfony\Component\EventDispatcher\EventDispatcher());
        }
    };
    $app = new App\Shared\Console\JsonConsoleApplication($kernel);
    $app->setAutoExit(false);
    $mode = $argv[2];
    putenv('APP_LOG_FORMAT='.($mode === 'plain' ? 'text' : 'json'));
    $command = new Symfony\Component\Console\Command\Command('fixture');
    $command->setCode(static function ($input, $output) use ($mode): int {
        $output->writeln('0 failed; Exception ERROR; quotes " and slash \\ and Unicode Привет');
        $output->write("multiline\nmessage");
        $output->writeln('{"message":"structured warning","level_name":"WARNING"}');
        if ($mode === 'throw') {
            throw new RuntimeException('fixture exception');
        }
        return $mode === 'fail' ? 7 : 0;
    });
    $app->addCommand($command);
    exit((new Symfony\Component\Runtime\Runner\Symfony\ConsoleApplicationRunner($app, 'test', new Symfony\Component\Console\Input\ArrayInput(['command' => 'fixture', '--no-interaction' => true]), new Symfony\Component\Console\Output\ConsoleOutput()))->run());
}

$check = static function (bool $condition, string $message): void {
    if (!$condition) {
        throw new RuntimeException($message);
    }
};
foreach (['ok' => 0, 'fail' => 7, 'throw' => 1, 'plain' => 0] as $mode => $expected) {
    $process = proc_open([PHP_BINARY, __FILE__, $argv[1] ?? $root.'/app/vendor/autoload.php', $mode], [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
    $stdout = stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    $stderr = stream_get_contents($pipes[2]);
    fclose($pipes[2]);
    $status = proc_close($process);
    $check($status === $expected, "$mode exit status $status: $stderr");
    if ($mode === 'plain') {
        $check(str_starts_with($stdout, '0 failed;'), 'Manual output must remain plain');
        continue;
    }
    $records = [];
    foreach (explode("\n", trim($stdout)) as $line) {
        $records[] = json_decode($line, true, flags: JSON_THROW_ON_ERROR);
    }
    $check($records[0]['level_name'] === 'INFO', 'Keywords must not turn INFO into ERROR');
    $check($records[1]['message'] === "multiline\nmessage", 'Multiline message must remain one JSON record');
    $check($records[2]['level_name'] === 'WARNING', 'Structured severity must survive without double encoding');
    $check($mode === 'ok' ? $stderr === '' : $stderr !== '', 'Failed commands need ERROR records');
    foreach (array_filter(explode("\n", $stderr)) as $line) {
        $record = json_decode($line, true, flags: JSON_THROW_ON_ERROR);
        $check($record['level_name'] === 'ERROR', 'Command failures must be ERROR');
    }
}
foreach (glob($root.'/docker/grafana/dashboards/*.json') as $path) {
    $dashboard = json_decode(file_get_contents($path), true, flags: JSON_THROW_ON_ERROR);
    foreach ($dashboard['panels'] ?? [] as $panel) {
        if (($panel['title'] ?? '') !== 'Recent application errors') {
            continue;
        }
        foreach ($panel['targets'] as $target) {
            $check(str_contains($target['expr'], '| json level_name="level_name" | __error__="" | level_name=~"ERROR|CRITICAL|ALERT|EMERGENCY"'), 'Overview must filter the parsed level_name');
        }
    }
}
echo "Structured logging tests passed.\n";
