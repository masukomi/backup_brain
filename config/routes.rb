Rails.application.routes.draw do
  resources :bookmarks do
    member do
      put "archive"
    end
  end
  get "bookmarks/tagged_with/:tags", controller: :bookmarks, action: :tagged_with, as: :bookmarks_tagged_with
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  root "bookmarks#index"


  match "/debugging/echo" => "debugging#echo", via: [:get, :post, :put, :patch, :delete]
end
