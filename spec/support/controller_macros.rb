module ControllerMacros
  def login_user
    before do
      @request.env["devise.mapping"] = Devise.mappings[:user]
      user = User.first || FactoryBot.create(:user)
      sign_in user
    end
  end
end
