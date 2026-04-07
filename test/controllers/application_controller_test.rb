require 'test_helper'

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  class TestController < ApplicationController
    def index
      render json: {uid: current_user.uid}
    end
  end

  test 'unauthorized' do
    with_routing do |set|
      set.draw do
        get '/test', to: 'application_controller_test/test#index'
      end

      get '/test'

      assert_response :unauthorized
    end
  end

  test 'authorized' do
    alice = users(:alice)

    with_routing do |set|
      set.draw do
        get '/test', to: 'application_controller_test/test#index'
      end

      get '/test', headers: {'Authorization' => "Bearer #{alice.api_key}"}

      assert_response :ok
      assert_equal 'alice', response.parsed_body['uid']
    end
  end

  test 'admin can login as proxy' do
    bob = users(:bob)

    with_routing do |set|
      set.draw do
        get '/test', to: 'application_controller_test/test#index'
      end

      get '/test', headers: {
        'Authorization'  => "Bearer #{bob.api_key}",
        'X-Dway-User-Id' => 'alice'
      }

      assert_response :ok
      assert_equal 'alice', response.parsed_body['uid']
    end
  end

  test 'non-admin cannot login as proxy' do
    alice = users(:alice)

    with_routing do |set|
      set.draw do
        get '/test', to: 'application_controller_test/test#index'
      end

      get '/test', headers: {
        'Authorization'  => "Bearer #{alice.api_key}",
        'X-Dway-User-Id' => 'bob'
      }

      assert_response :ok
      assert_equal 'alice', response.parsed_body['uid']
    end
  end
end
