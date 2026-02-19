post '/train/:unit_type' do
  redirect '/login' unless current_user

  unit_type = param[:unit_type].to_s
  unless UNIT_ORDER.include?(unit_type)
    set_notice('Unknown unit type.')
    redirect '/kingdom'
  end

  kingdom = db.get_first_row('SELECT * FROM kingdoms WHERE user_id = ?', current_user['id'])
  redirect '/login' unless kingdom