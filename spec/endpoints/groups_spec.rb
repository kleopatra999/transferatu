require "spec_helper"

describe Transferatu::Endpoints::Groups do
  include Rack::Test::Methods

  def app
    Transferatu::Endpoints::Groups
  end

  let(:log_url)      { 'https://token:t.8cda5772-ba01-49ec-9431-4391a067a0d3@example.com/logs' }
  let(:backup_limit) { 13 }

  before do
    @user = create(:user)
    @group = create(:group, user: @user)
    Transferatu::RequestStore.current_user = @user
  end

  describe "GET /groups" do
    it "succeeds" do
      get "/groups"
      expect(last_response.status).to eq(200)
    end
  end

  describe "GET /groups/:name" do
    it "succeeds" do
      get "/groups/#{@group.name}"
      expect(last_response.status).to eq(200)
    end
  end

  describe "POST /groups" do
    before do
      header "Content-Type", "application/json"
    end
    it "succeeds" do
      post "/groups", JSON.generate(name: 'foo', log_input_url: log_url,
                                    backup_limit: backup_limit)
      expect(last_response.status).to eq(201)
    end
    it "responds with 409 Conflict if group already exists" do
      post "/groups", JSON.generate(name: @group.name, log_input_url: log_url,
                                    backup_limit: backup_limit)
      expect(last_response.status).to eq(409)
    end
    it "undeletes existing groups when there is a conflict" do
      @group.destroy
      expect(@group.deleted?).to be true
      other_log_url = 'https://token:foo@example.com/logs'
      post "/groups", JSON.generate(name: @group.name, log_input_url: other_log_url,
                                    backup_limit: backup_limit)
      expect(last_response.status).to eq(201)
      @group.reload
      expect(@group.deleted?).to be false
      expect(@group.log_input_url).to eq(other_log_url)
    end
  end

  describe "DELETE /groups/:name" do
    it "succeeds" do
      delete "/groups/#{@group.name}"
      expect(last_response.status).to eq(200)
    end
    it "responds with 404 on missing groups" do
      delete "/groups/not-a-real-group"
      expect(last_response.status).to eq(404)
    end
  end
end
