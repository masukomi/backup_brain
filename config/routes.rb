Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  get "bookmarks/search", controller: :bookmarks, action: :search, as: :bookmarks_search
  get "bookmarks/tagged_with/:tags", controller: :bookmarks, action: :tagged_with, as: :bookmarks_tagged_with
  resources :bookmarks do
    member do
      put "archive"
    end
  end



  # Defines the root path route ("/")
  root "bookmarks#index"


  match "/debugging/echo" => "debugging#echo", via: [:get, :post, :put, :patch, :delete]
end
