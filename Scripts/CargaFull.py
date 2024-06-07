from pyspark.sql import SparkSession
from pyspark.sql.functions import col
from pyspark.sql.types import StringType
import os
import datetime

# Configurações
jdbcHostname = dbutils.secrets.get(scope="kvdataviziomvp", key="sql-host-onpremises")
jdbcPort = 1433
jdbcDatabase = "CorporeRM"
jdbcUsername = dbutils.secrets.get(scope="kvdataviziomvp", key="sql-username-onpremises")
jdbcPassword = dbutils.secrets.get(scope="kvdataviziomvp", key="sql-password-onpremises")

# Construa o URL JDBC
jdbcUrl = f"jdbc:sqlserver://{jdbcHostname}:{jdbcPort};database={jdbcDatabase}"

# Tabelas a serem extraídas
tables = ["GCCUSTO", "PPESSOA", "PFUNC", "PFUNCAO", "PSECAO"]

# Inicializa Spark
spark = SparkSession.builder.appName("FullLoad").getOrCreate()

# Função para extrair e salvar tabela
def extract_and_save_table(table):
    df = (spark.read.format("jdbc")
          .option("url", jdbcUrl)
          .option("dbtable", f"dbo.{table}")
          .option("user", jdbcUsername)
          .option("password", jdbcPassword)
          .load())

    # Adiciona coluna de data de carga
    df = df.withColumn("LOAD_DATE", current_timestamp())

    # Salva no container bronze
    output_path = f"abfss://bronze@stdataviziomvp1717508749.dfs.core.windows.net/totvsrm/{table}.parquet"
    df.write.mode("overwrite").parquet(output_path)

for table in tables:
    extract_and_save_table(table)
