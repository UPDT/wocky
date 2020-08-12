sudo apt-get install wget
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb && sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt-get update
sudo apt-get install esl-erlang
sudo apt-get install elixir
sudo apt-get install build-essential
sudo apt-get install postgresql
sudo apt-get install postgis
sudo apt-get install redis
sudo apt-get install git
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'password';"
mix deps.get
mix ecto.setup
mix compile
