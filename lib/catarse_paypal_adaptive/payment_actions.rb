module CatarsePaypalAdaptive
  class PaymentActions
    include PayPal::SDK::AdaptivePayments

    def initialize payment
      @payment = payment
    end

    def process_payment
      percent = (@payment.contribution.project.category.percentage_path_fee || ((CatarseSettings.get_without_cache(:catarse_fee) || 0.05) * 100) rescue ((CatarseSettings.get_without_cache(:catarse_fee) || 0.05) * 100)).to_f
      
      path_amount = @payment.value.to_f * percent / 100
      project_owner_amount = @payment.value - path_amount   

      if path_amount > 0 && @payment.contribution.project.account.email != CatarseSettings.get_without_cache(:paypal_receiver_email)
        pay = api.build_pay({
                              :actionType => "PAY",
                              :cancelUrl => CatarsePaypalAdaptive::Engine.routes.url_helpers.payment_callback_paypal_adaptive_url(id: @payment.contribution.id, protocol: (Rails.env.production? ? "https" : "http"), host: CatarseSettings.get_without_cache(:host), status: 'CANCELED'),
                              :returnUrl => CatarsePaypalAdaptive::Engine.routes.url_helpers.payment_callback_paypal_adaptive_url(id: @payment.contribution.id, protocol: (Rails.env.production? ? "https" : "http"), host: CatarseSettings.get_without_cache(:host), status: 'SUCCEEDED'),
                              :currencyCode => "USD",
                              :memo => "Support project #{@payment.contribution.project.name} on Philamthropy",
                              :feesPayer => "PRIMARYRECEIVER",
                              :senderEmail => @payment.contribution.payer_email,
                              :preapprovalKey => @payment.payment_token,
                              :receiverList =>  {
                                                  :receiver =>  [ { :amount => @payment.value.to_f,
                                                                    :email => @payment.contribution.project.account.email,
                                                                    :primary => true },
                                                                  { :amount => path_amount,
                                                                    :email => CatarseSettings.get_without_cache(:paypal_receiver_email),
                                                                    :primary => false }
                                                                ] 
                                                }
                            })
      else
        pay = api.build_pay({
                              :actionType => "PAY",
                              :cancelUrl => CatarsePaypalAdaptive::Engine.routes.url_helpers.payment_callback_paypal_adaptive_url(id: @payment.contribution.id, protocol: (Rails.env.production? ? "https" : "http"), host: CatarseSettings.get_without_cache(:host), status: 'CANCELED'),
                              :returnUrl => CatarsePaypalAdaptive::Engine.routes.url_helpers.payment_callback_paypal_adaptive_url(id: @payment.contribution.id, protocol: (Rails.env.production? ? "https" : "http"), host: CatarseSettings.get_without_cache(:host), status: 'SUCCEEDED'),
                              :currencyCode => "USD",
                              :memo => "Support project #{@payment.contribution.project.name} on Philamthropy",
                              :feesPayer => "EACHRECEIVER",
                              :senderEmail => @payment.contribution.payer_email,
                              :preapprovalKey => @payment.payment_token,
                              :receiverList =>  {
                                                  :receiver =>  [{
                                                                  :amount => @payment.value.to_f,
                                                                  :email => @payment.contribution.project.account.email
                                                                }] 
                                                }
                            })
      end
      @pay_response = api.pay(pay)

      # Access Response
      if @pay_response.success?
        PaymentEngines.create_payment_notification contribution_id: @payment.contribution.id, extra_data: @pay_response.to_hash
        @payment.update_attributes({key: @pay_response.payKey, payment_processed: true, paid_at: Time.now})
        return true
      else
        if @payment.pay_failed_count.to_i > 10
          @payment.update_attributes({state: 'refused', refused_at: Time.now})
          PaymentEngines.create_payment_notification contribution_id: contribution.id, extra_data: {:error => "REFUSED over 10 retries"}
          return true
        else
          @payment.update_attributes({pay_failed_count: @payment.pay_failed_count.to_i + 1})
          PaymentEngines.create_payment_notification contribution_id: @payment.contribution.id, extra_data: @pay_response.to_hash
          return false
        end
      end
    end

    def cancel_payment
      cancel_preapproval = api.build_cancel_preapproval({:preapprovalKey => @payment.payment_token })

      # Make API call & get response
      @cancel_preapproval_response = api.cancel_preapproval(cancel_preapproval)

      # Access Response
      if @cancel_preapproval_response.success?
        PaymentEngines.create_payment_notification contribution_id: @payment.contribution.id, extra_data: @cancel_preapproval_response.to_hash
        @payment.update_attributes({state: 'refunded', refunded_at: Time.now})
        return true
      else
        PaymentEngines.create_payment_notification contribution_id: @payment.contribution.id, extra_data: @cancel_preapproval_response.to_hash
        return false
      end
    end

    private

    def api
      @api ||= API.new
    end

  end
end
