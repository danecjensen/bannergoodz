json.extract! product, :id, :title, :type, :created_at, :updated_at
json.url product_url(product, format: :json)