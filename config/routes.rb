Rails.application.routes.draw do
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  get "bookmarks/search", controller: :bookmarks, action: :search, as: :bookmarks_search
  get "bookmarks/tagged_with/:tags", controller: :bookmarks, action: :tagged_with, as: :bookmarks_tagged_with
  get "bookmarks/unarchived", controller: :bookmarks, action: :unarchived, as: :bookmarks_unarchived
  get "bookmarks/to_read", controller: :bookmarks, action: :to_read, as: :bookmarks_to_read

  # a trivially small success page which expects to be closed immediately
  # by the plugin
  get "bookmarks/success", controller: :bookmarks, action: :success, as: :bookmarks_success
  get "bookmarks/:id/archive", controller: :bookmarks, action: :archive, as: :bookmarks_archive, via: [:post, :put]

  resources :bookmarks do
    member do
      put "archive"
      get "download"
      put "mark_as_read"
      put "mark_to_read"
    end
  end

  resources :settings
  resources :tags

  get "archives/:object_type/:id/:filename", controller: :archives, action: :show

  get "importer", controller: :importer, action: :index, as: :importer_form
  post "importer/import", controller: :importer, action: :import, as: :importer_import

  match "/debugging/echo" => "debugging#echo", via: [:get, :post, :put, :patch, :delete]

  # Tell those script kiddes to fuck off.
  # Is this needed? no.
  # Does it work? Depends on how you define "work"
  # It does save bandwidth & cycles and makes my villainous heart cackle.
  get "*env",        controller: :script_kiddies, action: :fuck_off
  get "*env;",       controller: :script_kiddies, action: :fuck_off
  get ".git/config", controller: :script_kiddies, action: :fuck_off
  get "*.php*",      controller: :script_kiddies, action: :fuck_off
  get "*.jsp*",      controller: :script_kiddies, action: :fuck_off




  # Defines the root path route ("/")
  root "bookmarks#index"


end
