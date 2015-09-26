class CatarsePaypalAdaptive::PaypalAdaptiveController < ApplicationController
  include PayPal::SDK::AdaptivePayments

  skip_before_filter :force_http
  skip_before_filter :verify_authenticity_token, :only => [:ipn]

  SCOPE = "projects.contributions.checkout"
  layout :false

  def ipn
    if PayPal::SDK::Core::API::IPN.valid?(request.raw_post) && (contribution.payment_method == 'PayPal' || contribution.payment_method.nil?)
      process_paypal_message params
      contribution.update_attributes(:payment_service_fee => params['mc_fee'], :payer_email => params['payer_email'])
    else
      return render status: 500, nothing: true
    end
    return render status: 200, nothing: true
  rescue Exception => e
    return render status: 500, text: e.inspect
  end

  def pay
    begin
      # Build request object
      @preapproval = @api.build_preapproval({
        :cancelUrl => cancel_paypal_adaptive_url(id: contribution.id, :protocol => (Rails.env.production? ? "http" : "https")),
        :currencyCode => "USD",
        :returnUrl => success_paypal_adaptive_url(id: contribution.id, :protocol => (Rails.env.production? ? "http" : "https")),
        :ipnNotificationUrl => ipn_paypal_adaptive_index_url(subdomain: 'www'),
        :startingDate => (Time.now + 5.minutes).strftime("%FZ"),
        :endingDate => (contribution.project.expires_at + 6.months).strftime("%FZ"),
        :maxNumberOfPayments => 2,
        :maxNumberOfPaymentsPerPeriod => 2,
        :maxAmountPerPayment => contribution.price_in_cents.to_f/100,
        :maxTotalAmountOfAllPayments => contribution.price_in_cents.to_f/100,
        :senderEmail => contribution.payer_email,
        :memo => "Support project #{contribution.project.name} on Philamthropy"
        :feesPayer => "SENDER" })

      # Make API call & get response
      @preapproval_response = @api.preapproval(@preapproval) if request.post?

      # Access Response
      if @preapproval_response.success?
        # @preapproval_response.preapprovalKey
        PaymentEngines.create_payment_notification contribution_id: contribution.id, extra_data: @preapproval_response.to_hash
        payment = contribution.payments.new gateway: 'Paypal', 
                                            payment_method: 'PayPal', 
                                            key: @preapproval_response.preapprovalKey, 
                                            state: 'pending',
                                            value: contribution.price_in_cents.to_f/100,
                                            installment_value: contribution.price_in_cents.to_f/100
        payment.save(validate: false)

        # redirect_to "https://www.paypal.com/webscr?cmd=_ap-preapproval&preapprovalkey=#{@preapproval_response.preapprovalKey}"
        # redirect_to "https://www.sandbox.paypal.com/webscr?cmd=_ap-preapproval&preapprovalkey=#{@preapproval_response.preapprovalKey}"
        redirect_to api.payment_url(@preapproval_response)  # Url to complete payment
      else
        # @preapproval_response.error
        PaymentEngines.create_payment_notification contribution_id: contribution.id, extra_data: @preapproval_response.to_hash
        Rails.logger.info "-----> #{response.error}"
        flash[:failure] = t('paypal_error', scope: SCOPE)
        return redirect_to main_app.new_project_contribution_path(contribution.project)
      end

    rescue Exception => e
      Rails.logger.info "-----> #{e.inspect}"
      flash[:failure] = t('paypal_error', scope: SCOPE)
      return redirect_to main_app.new_project_contribution_path(contribution.project)
    end
  end

  def pay_old
    begin
      @pay = api.build_pay({
        :actionType => "PAY",
        :cancelUrl => cancel_paypal_adaptive_url(id: contribution.id),
        :currencyCode => "EUR",
        :feesPayer => "SENDER",
        :ipnNotificationUrl => ipn_paypal_adaptive_index_url(subdomain: 'www'),
        :receiverList => {
          :receiver => [{
            :amount => contribution.price_in_cents.to_f/100,
            :email => contribution.payer_email }] },
        :returnUrl => success_paypal_adaptive_url(id: contribution.id) })

      response = api.pay(@pay) if request.post?
      
      PaymentEngines.create_payment_notification contribution_id: contribution.id, extra_data: response.to_hash
      
      if response.success? && response.payment_exec_status != "ERROR"
        contribution.update_attributes payment_method: 'PayPal', payment_token: response.payKey
        redirect_to api.payment_url(response)  # Url to complete payment
      else
        Rails.logger.info "-----> #{response.error}"
        flash[:failure] = t('paypal_error', scope: SCOPE)
        return redirect_to main_app.new_project_contribution_path(contribution.project)
      end
      
    rescue Exception => e
      Rails.logger.info "-----> #{e.inspect}"
      flash[:failure] = t('paypal_error', scope: SCOPE)
      return redirect_to main_app.new_project_contribution_path(contribution.project)
    end
  end

  def success
    begin
      payment = contribution.payments.last
      @preapproval_details = api.build_preapproval_details(:preapprovalKey => payment.key)
      @preapproval_details_response = api.preapproval_details(@preapproval_details) if request.post?
      if @preapproval_details_response.success? && @preapproval_details_response.status == 'ACTIVE' && @preapproval_details_response.approved == true
        payment.update_attributes(state: 'paid', payment_token: payment.key)
        flash[:success] = t('success', scope: SCOPE)
        redirect_to main_app.project_contribution_path(project_id: contribution.project.id, id: contribution.id)
      else
        payment.update_attributes(state: 'refused')
        PaymentEngines.create_payment_notification contribution_id: contribution.id, extra_data: @preapproval_response.to_hash
        flash[:failure] = t('paypal_error', scope: SCOPE)
        return redirect_to main_app.new_project_contribution_path(contribution.project)
      end
    rescue Exception => e
      payment.update_attributes(state: 'refused')
      Rails.logger.info "-----> #{e.inspect}"
      flash[:failure] = t('paypal_error', scope: SCOPE)
      return redirect_to main_app.new_project_contribution_path(contribution.project)
    end  
  end

  def success_old
    begin
      payment_details = api.build_payment_details(:payKey => contribution.payment_token)
      response = api.payment_details(payment_details)
      
      PaymentEngines.create_payment_notification contribution_id: contribution.id, extra_data: response.to_hash
         
      if response.success? && response.status == 'COMPLETED'
        # contribution.update_attributes payment_id: purchase.params['transaction_id'] if purchase.params['transaction_id']
        contribution.confirm!

        flash[:success] = t('success', scope: SCOPE)
        redirect_to main_app.project_contribution_path(project_id: contribution.project.id, id: contribution.id)
      else 
        flash[:failure] = t('paypal_error', scope: SCOPE)
        redirect_to main_app.new_project_contribution_path(contribution.project)
      end      
    rescue Exception => e
      Rails.logger.info "-----> #{e.inspect}"
      flash[:failure] = t('paypal_error', scope: SCOPE)
      return redirect_to main_app.new_project_contribution_path(contribution.project)
    end
  end

  def cancel
    payment = contribution.payments.last
    payment.update_attributes(state: 'refused')
    PaymentEngines.create_payment_notification contribution_id: contribution.id, extra_data: {:status => "CANCELED"}

    flash[:failure] = t('paypal_cancel', scope: SCOPE)
    redirect_to main_app.new_project_contribution_path(contribution.project)
  end

  def cancel_old
    PaymentEngines.create_payment_notification contribution_id: contribution.id, extra_data: response.to_hash
    flash[:failure] = t('paypal_cancel', scope: SCOPE)
    redirect_to main_app.new_project_contribution_path(contribution.project)
  end

  def contribution
    @contribution ||= if params['id']
                  # PaymentEngines.find_payment(id: params['id'])
                  PaymentEngines.find_contribution(params['id'])
                elsif params['txn_id']
                  PaymentEngines.find_payment(payment_id: params['txn_id']) || (params['parent_txn_id'] && PaymentEngines.find_payment(payment_id: params['parent_txn_id']))
                end
  end


  private

  def api
    @api ||= API.new
  end
  
end
