module StripeMock
  module RequestHandlers
    module Subscriptions

      def Subscriptions.included(klass)
        klass.add_handler 'get /v1/customers/(.*)/subscriptions', :retrieve_subscriptions
        klass.add_handler 'post /v1/customers/(.*)/subscriptions', :create_subscription
        klass.add_handler 'get /v1/customers/(.*)/subscriptions/(.*)', :retrieve_subscription
        klass.add_handler 'post /v1/customers/(.*)/subscriptions/(.*)', :update_subscription
        klass.add_handler 'delete /v1/customers/(.*)/subscriptions/(.*)', :cancel_subscription
      end

      def create_subscription(route, method_url, params, headers)
        route =~ method_url
        customer = assert_existance :customer, $1, customers[$1]

        plan_id = params[:plan]
        plan = assert_existance :plan, plan_id, plans[plan_id]

        if params[:card]
          new_card = get_card_by_token(params.delete(:card))
          add_card_to_object(:customer, new_card, customer)
          customer[:default_card] = new_card[:id]
        end

        if params[:coupon]
          coupon = assert_existance :coupon, params[:coupon], coupons[params[:coupon]]
        end

        # Ensure customer has card to charge if plan has no trial and is not free
        verify_card_present(customer, plan, params)

        subscription = Data.mock_subscription({ id: (params[:id] || new_id('su')) })
        subscription.merge!(custom_subscription_params(plan, customer, params))
        add_subscription_to_customer(customer, subscription)

        subscription
      end

      def retrieve_subscription(route, method_url, params, headers)
        route =~ method_url

        customer = assert_existance :customer, $1, customers[$1]
        assert_existance :subscription, $2, get_customer_subscription(customer, $2)
      end

      def retrieve_subscriptions(route, method_url, params, headers)
        route =~ method_url

        customer = assert_existance :customer, $1, customers[$1]
        customer[:subscriptions]
      end

      def update_subscription(route, method_url, params, headers)
        route =~ method_url
        customer = assert_existance :customer, $1, customers[$1]

        subscription = get_customer_subscription(customer, $2)
        assert_existance :subscription, $2, subscription

        if params[:card]
          new_card = get_card_by_token(params.delete(:card))
          add_card_to_object(:customer, new_card, customer)
          customer[:default_card] = new_card[:id]
        end

        # expand the plan for addition to the customer object
        plan_name = params[:plan] || subscription[:plan][:id]
        plan = plans[plan_name]

        assert_existance :plan, plan_name, plan
        params[:plan] = plan if params[:plan]
        verify_card_present(customer, plan)

        if subscription[:cancel_at_period_end]
          subscription[:cancel_at_period_end] = false
          subscription[:canceled_at] = nil
        end

        subscription.merge!(custom_subscription_params(plan, customer, params))

        # delete the old subscription, replace with the new subscription
        customer[:subscriptions][:data].reject! { |sub| sub[:id] == subscription[:id] }
        customer[:subscriptions][:data] << subscription

        subscription
      end

      def cancel_subscription(route, method_url, params, headers)
        route =~ method_url
        customer = assert_existance :customer, $1, customers[$1]

        subscription = get_customer_subscription(customer, $2)
        assert_existance :subscription, $2, subscription

        cancel_params = { canceled_at: Time.now.utc.to_i }
        cancelled_at_period_end = (params[:at_period_end] == true)
        if cancelled_at_period_end
          cancel_params[:cancel_at_period_end] = true
        else
          cancel_params[:status] = "canceled"
          cancel_params[:cancel_at_period_end] = false
          cancel_params[:ended_at] = Time.now.utc.to_i
        end

        subscription.merge!(cancel_params)

        unless cancelled_at_period_end
          delete_subscription_from_customer customer, subscription
        end

        subscription
      end

      private

      def verify_card_present(customer, plan, params={})
        if customer[:default_card].nil? && plan[:trial_period_days].nil? && plan[:amount] != 0 && plan[:trial_end].nil? && params[:trial_end].nil?
          raise Stripe::InvalidRequestError.new('You must supply a valid card xoxo', nil, 400)
        end
      end

    end
  end
end
