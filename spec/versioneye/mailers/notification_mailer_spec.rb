require 'spec_helper'

describe NotificationMailer do

  describe 'new_version_email' do

    it 'should have the title of the post' do

      user = UserFactory.create_new
      notification = NotificationFactory.create_new user
      notifications = Notification.unsent_user_notifications user

      product = notification.product

      project = ProjectFactory.create_new user
      project_dep = Projectdependency.new({:language => product.language, :prod_key => product.prod_key, :project_id => project.id })
      project_dep.save

      email = NotificationMailer.new_version_email(user, notifications)

      email.to.should eq( [user.email] )
      email.encoded.should include( "Hello #{user.fullname}" )
      email.encoded.should include( 'There are new releases out there' )
      email.encoded.should include( '?utm_medium=email' )
      email.encoded.should include( 'utm_source=new_version' )
      email.encoded.should include( product.name )
      email.encoded.should include( notification.version_id )
      email.encoded.should include( "/user/projects/#{project._id.to_s}" )
      email.encoded.should include( "http://localhost:3000" )

      ActionMailer::Base.deliveries.clear
      email.deliver_now!
      ActionMailer::Base.deliveries.size.should == 1
    end

  end

  describe 'status' do

    it 'should have the title of the post' do

      email = NotificationMailer.status(1000)

      email.encoded.should include( "Hey Admin Dude" )
      email.encoded.should include( 'Today we send out 1000 notification E-Mails' )
      email.encoded.should include( 'Your VersionEye Team' )
      email.encoded.should include( 'CEO' )
      email.encoded.should include( 'Robert Reiz' )

      ActionMailer::Base.deliveries.clear
      email.deliver_now!
      ActionMailer::Base.deliveries.size.should == 1
    end

  end

end
