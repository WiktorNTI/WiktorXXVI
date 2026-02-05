get '/tutorial/start' do
  redirect '/login' unless current_user
  slim :tutorial_start
end

post '/tutorial/choice' do
  redirect '/login' unless current_user

  choice = params[:choice].to_s
  kingdom = db.get_first_row('SELECT id FROM kingdoms WHERE user_id = ?', current_user['id'])
  redirect '/login' unless current_user

  if choice == 'yes'
    db.execute(
      'UPDATE kingdoms SET tutorial_mode = ?, tutorial_step = ? WHERE id = ?',
      'guided', 1, kingdom['id']
    )
    redirect '/tutorial'
  else
  grant_starter_pack!(kingdom['id'])
  db.execute(
    'UPDATE kingdoms SET tutorial_mode = ?, tutorial_step = ? WHERE id = ?',
    'done', 0, kingdom['id']
  )
  redirect '/kingdom'
end

get 'tutorial' do
  redirect '/login' unless current_user

  kingdom = db.get_first_row('SELECT id, tutorial_mode, tutorial_step FROM kingdoms WHERE user_id = ?'), current_user['id'])