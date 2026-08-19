<?php

declare(strict_types=1);

namespace App\Tests\Feature;

use Symfony\Bundle\FrameworkBundle\Test\WebTestCase;
use Symfony\Component\HttpFoundation\Response;

final class ProductApiTest extends WebTestCase
{
    public function testCreateAndListProducts(): void
    {
        $client = self::createClient();

        $payload = [
            'name' => 'Test product '.uniqid(more_entropy: true),
            'price' => '9.99',
        ];

        $client->request(
            method: 'POST',
            uri: '/products',
            server: ['CONTENT_TYPE' => 'application/json'],
            content: json_encode(value: $payload, flags: JSON_THROW_ON_ERROR),
        );

        self::assertResponseStatusCodeSame(Response::HTTP_CREATED);

        $created = json_decode(json: $client->getResponse()->getContent(), associative: true, flags: JSON_THROW_ON_ERROR);

        self::assertIsArray($created);
        self::assertArrayHasKey('id', $created);
        self::assertIsInt($created['id']);
        self::assertSame($payload['name'], $created['name']);
        self::assertSame($payload['price'], $created['price']);

        $client->request(method: 'GET', uri: '/products');

        self::assertResponseIsSuccessful();

        $list = json_decode(json: $client->getResponse()->getContent(), associative: true, flags: JSON_THROW_ON_ERROR);

        self::assertIsArray($list);
        self::assertNotEmpty($list);

        $found = false;

        foreach ($list as $item) {
            if (!is_array(value: $item) || !array_key_exists(key: 'id', array: $item)) {
                continue;
            }

            if ($item['id'] === $created['id']) {
                $found = true;
                break;
            }
        }

        self::assertTrue($found, 'Created product should be present in products list response.');
    }
}
