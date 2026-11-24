from django.contrib import admin

from logistic.models import Product, Stock, StockProduct


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ['id', 'title', 'description']
    search_fields = ['title', 'description']


class StockProductInline(admin.TabularInline):
    model = StockProduct
    extra = 1


@admin.register(Stock)
class StockAdmin(admin.ModelAdmin):
    list_display = ['id', 'address']
    search_fields = ['address']
    inlines = [StockProductInline]
