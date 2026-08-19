<?php

declare(strict_types=1);

namespace App\Controller;

use App\Entity\Product;
use App\Message\ProductCreatedMessage;
use App\Repository\ProductRepository;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\Messenger\MessageBusInterface;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Contracts\Cache\CacheInterface;
use Symfony\Contracts\Cache\ItemInterface;

#[Route('/products', name: 'product_')]
class ProductController extends AbstractController
{
    #[Route('', name: 'list', methods: ['GET'])]
    public function list(
        ProductRepository $repository,
        CacheInterface $cache,
    ): JsonResponse {
        $this->simulateLatencyAndFailures();

        $useCache = random_int(min: 1, max: 100) <= 60;

        if ($useCache) {
            $products = $cache->get(
                'products_latest_50',
                function (ItemInterface $item) use ($repository): array {
                    $item->expiresAfter(5);

                    $entities = $repository->findBy(criteria: [], orderBy: ['id' => 'DESC'], limit: 50);

                    return array_map(
                        callback: $this->normalizeProduct(...),
                        array: $entities,
                    );
                },
            );
        } else {
            $entities = $repository->findBy(criteria: [], orderBy: ['id' => 'DESC'], limit: 50);

            $products = array_map(
                callback: $this->normalizeProduct(...),
                array: $entities,
            );
        }

        return $this->json(data: $products);
    }

    #[Route('', name: 'create', methods: ['POST'])]
    public function create(Request $request, EntityManagerInterface $em, MessageBusInterface $bus): JsonResponse
    {
        $this->simulateLatencyAndFailures();

        $data = json_decode(json: (string) $request->getContent(), associative: true, flags: JSON_THROW_ON_ERROR);

        if (!isset($data['name'], $data['price']) || !is_string(value: $data['name']) || !is_numeric(value: $data['price'])) {
            return $this->json(data: ['error' => 'Invalid payload'], status: Response::HTTP_BAD_REQUEST);
        }

        $product = new Product(name: $data['name'], price: (string) $data['price']);

        $em->persist($product);
        $em->flush();

        $bus->dispatch(new ProductCreatedMessage(id: $product->getId(), name: $product->getName(), price: $product->getPrice()));

        return $this->json(
            data: [
                'id' => $product->getId(),
                'name' => $product->getName(),
                'price' => $product->getPrice(),
                'createdAt' => $product->getCreatedAt()->format(format: \DATE_ATOM),
                'updatedAt' => $product->getUpdatedAt()?->format(\DATE_ATOM),
            ],
            status: Response::HTTP_CREATED,
        );
    }

    private function simulateLatencyAndFailures(): void
    {
        $appEnv = $_SERVER['APP_ENV'] ?? $_ENV['APP_ENV'] ?? null;

        if ('test' === $appEnv) {
            return;
        }

        $roll = random_int(min: 1, max: 100);

        if ($roll <= 5) {
            usleep(microseconds: random_int(min: 400000, max: 1200000));

            throw new \RuntimeException(message: 'Random failure for observability demo');
        }

        if ($roll <= 35) {
            usleep(microseconds: random_int(min: 50000, max: 400000));
        }
    }

    /**
     * @return array{id: int|null, name: string, price: string, createdAt: string, updatedAt: string|null}
     */
    private function normalizeProduct(Product $product): array
    {
        return [
            'id' => $product->getId(),
            'name' => $product->getName(),
            'price' => $product->getPrice(),
            'createdAt' => $product->getCreatedAt()->format(format: \DATE_ATOM),
            'updatedAt' => $product->getUpdatedAt()?->format(\DATE_ATOM),
        ];
    }
}
