from rest_framework.test import APITestCase

from logistic.models import StockProduct


class StocksProductsApiTest(APITestCase):
    def setUp(self):
        self.tomato = self.client.post(
            '/api/v1/products/',
            {'title': 'Помидор', 'description': 'Лучшие помидоры на рынке'},
            format='json',
        ).json()
        self.cucumber = self.client.post(
            '/api/v1/products/', {'title': 'Огурец', 'description': 'Хрустящий'}, format='json'
        ).json()
        self.milk = self.client.post('/api/v1/products/', {'title': 'Молоко'}, format='json').json()

    def create_stock(self, address, positions):
        response = self.client.post(
            '/api/v1/stocks/', {'address': address, 'positions': positions}, format='json'
        )
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()

    def test_products_crud_and_search(self):
        response = self.client.get('/api/v1/products/')
        self.assertEqual(response.json()['count'], 3)

        response = self.client.patch(
            f"/api/v1/products/{self.tomato['id']}/",
            {'description': 'Самые сочные и ароматные помидорки'},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['description'], 'Самые сочные и ароматные помидорки')

        found = self.client.get('/api/v1/products/', {'search': 'помидор'}).json()['results']
        self.assertEqual([p['id'] for p in found], [self.tomato['id']])
        found = self.client.get('/api/v1/products/', {'search': 'хруст'}).json()['results']
        self.assertEqual([p['id'] for p in found], [self.cucumber['id']])

        response = self.client.delete(f"/api/v1/products/{self.milk['id']}/")
        self.assertEqual(response.status_code, 204)
        self.assertEqual(self.client.get('/api/v1/products/').json()['count'], 2)

    def test_stock_create_and_update_positions(self):
        stock = self.create_stock(
            'Ленинград, ул. Пушкина, 1',
            [
                {'product': self.tomato['id'], 'quantity': 250, 'price': 120.50},
                {'product': self.cucumber['id'], 'quantity': 100, 'price': 180},
            ],
        )
        self.assertEqual(len(stock['positions']), 2)

        response = self.client.patch(
            f"/api/v1/stocks/{stock['id']}/",
            {
                'positions': [
                    {'product': self.tomato['id'], 'quantity': 100, 'price': 130.80},
                    {'product': self.milk['id'], 'quantity': 243, 'price': 145},
                ]
            },
            format='json',
        )
        self.assertEqual(response.status_code, 200, response.content)
        position = StockProduct.objects.get(stock_id=stock['id'], product_id=self.tomato['id'])
        self.assertEqual((position.quantity, str(position.price)), (100, '130.80'))
        self.assertEqual(StockProduct.objects.filter(stock_id=stock['id']).count(), 3)

        # PATCH без позиций меняет только адрес
        response = self.client.patch(
            f"/api/v1/stocks/{stock['id']}/", {'address': 'Новый адрес'}, format='json'
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json()['address'], 'Новый адрес')
        self.assertEqual(len(response.json()['positions']), 3)

        response = self.client.delete(f"/api/v1/stocks/{stock['id']}/")
        self.assertEqual(response.status_code, 204)
        self.assertFalse(StockProduct.objects.filter(stock_id=stock['id']).exists())

    def test_stock_search_by_product(self):
        first = self.create_stock('Склад 1', [{'product': self.tomato['id'], 'quantity': 1, 'price': 10}])
        second = self.create_stock('Склад 2', [{'product': self.cucumber['id'], 'quantity': 1, 'price': 10}])
        self.create_stock('Склад 3', [{'product': self.milk['id'], 'quantity': 1, 'price': 10}])

        def ids(**params):
            return [s['id'] for s in self.client.get('/api/v1/stocks/', params).json()['results']]

        self.assertEqual(ids(products=self.tomato['id']), [first['id']])
        # дополнительное задание: по части названия или описания
        self.assertEqual(ids(products='помид'), [first['id']])
        self.assertEqual(ids(products='ХРУСТ'), [second['id']])
        self.assertEqual(ids(search='огур'), [second['id']])

    def test_pagination_and_root_redirect(self):
        for i in range(12):
            self.client.post('/api/v1/products/', {'title': f'Товар {i}'}, format='json')
        page = self.client.get('/api/v1/products/').json()
        self.assertEqual(page['count'], 15)
        self.assertEqual(len(page['results']), 10)
        self.assertIsNotNone(page['next'])

        response = self.client.get('/')
        self.assertEqual(response.status_code, 302)
        self.assertEqual(response['Location'], '/api/v1/')
