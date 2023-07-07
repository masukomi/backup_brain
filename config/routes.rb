Rails.application.routes.draw do
  resources :bookmarks
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"
  match "/debugging/echo" => "debugging#echo", via: [:get, :post, :put, :patch, :delete]
end
