sudo apt-get -y install wget
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb && sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt-get update
sudo apt-get -y install esl-erlang
sudo apt-get -y install elixir
sudo apt-get -y install build-essential
sudo apt-get -y install postgresql
sudo apt-get -y install postgis
sudo apt-get -y install redis
sudo apt-get -y install git
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'password';"
mix deps.get
mix ecto.setup
mix compile
