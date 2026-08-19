<?php

declare(strict_types=1);

namespace App\MessageHandler;

use App\Message\ProductCreatedMessage;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler]
final class ProductCreatedMessageHandler
{
    public function __invoke(ProductCreatedMessage $message): void
    {
        $roll = random_int(min: 1, max: 100);

        if ($roll <= 10) {
            usleep(microseconds: random_int(min: 300000, max: 1000000));

            throw new \RuntimeException(message: 'Random failure in ProductCreatedMessageHandler');
        }

        if ($roll <= 40) {
            usleep(microseconds: random_int(min: 50000, max: 300000));
        }

        // In a real app we might, for example, send an email or update a search index here.
    }
}
