<?php

declare(strict_types=1);

namespace App\Tests\Architecture;

use PHPat\Selector\Selector;
use PHPat\Test\Builder\Rule;
use PHPat\Test\PHPat;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;

final class ModuleBoundariesTest
{
    public function controllersShouldExtendAbstractController(): Rule
    {
        return PHPat::rule()
            ->classes(Selector::inNamespace('App\\Controller'))
            ->should()->extend()
            ->classes(Selector::classname(AbstractController::class))
            ->because('Symfony HTTP entrypoints should share one explicit controller base');
    }

    public function messagesShouldNotDependOnHttpOrPersistenceLayers(): Rule
    {
        return PHPat::rule()
            ->classes(Selector::inNamespace('App\\Message'))
            ->shouldNot()->dependOn()
            ->classes(
                Selector::inNamespace('App\\Controller'),
                Selector::inNamespace('App\\Repository'),
            )
            ->because('messages should stay transport-friendly and independent from delivery or persistence details');
    }

    public function messageHandlersShouldOnlyDependOnMessagesAndSymfony(): Rule
    {
        return PHPat::rule()
            ->classes(Selector::inNamespace('App\\MessageHandler'))
            ->canOnly()->dependOn()
            ->classes(
                Selector::inNamespace('App\\Message'),
                Selector::inNamespace('Symfony'),
            )
            ->because('message handlers should orchestrate message handling without reaching into unrelated layers');
    }
}
