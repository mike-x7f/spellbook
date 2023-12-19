{{
  config(
    
    alias='ccip_reverted_transactions',
    partition_by=['date_month'],
    materialized='incremental',
    file_format='delta',
    incremental_strategy='merge',
    unique_key=['tx_hash', 'node_address']
  )
}}

{% set incremental_interval = '7' %}

WITH
  optimism_usd AS (
    SELECT
      minute as block_time,
      price as usd_amount
    FROM
      {{ source('prices', 'usd') }} price
    WHERE
      symbol = 'ETH'
      {% if is_incremental() %}
        AND minute >= date_trunc('day', now() - interval '{{incremental_interval}}' day)
      {% endif %}      
  ),
  ccip_reverted_transactions AS (
    SELECT
      tx.tx_hash as tx_hash,
      MAX(tx.block_time) as block_time,
      cast(date_trunc('month', MAX(tx.block_time)) as date) as date_month,
      tx."from" as "node_address",
      MAX((cast((l1_gas_used) as double) / 1e18) * l1_gas_price) as token_amount,
      MAX(optimism_usd.usd_amount) as usd_amount
    FROM
      {{ ref('chainlink_optimism_ccip_send_traces') }} tx
      INNER JOIN {{ source('optimism', 'transactions') }} tx2 ON tx2.hash = tx.tx_hash
      {% if is_incremental() %}
        AND tx2.block_time >= date_trunc('day', now() - interval '{{incremental_interval}}' day)
      {% endif %}
      LEFT JOIN optimism_usd ON date_trunc('minute', tx.block_time) = optimism_usd.block_time
    WHERE
      tx.tx_success = false
      {% if is_incremental() %}
        AND tx.block_time >= date_trunc('day', now() - interval '{{incremental_interval}}' day)
      {% endif %}      
    GROUP BY
      tx.tx_hash,
      tx."from"
  )
SELECT
 'optimism' as blockchain,
  block_time,
  date_month,
  node_address,
  token_amount,
  usd_amount,
  tx_hash
FROM
  ccip_reverted_transactions