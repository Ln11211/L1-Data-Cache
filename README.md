# L1 Data Cache
A Verilog project that implements and tests two cache organizations: Direct Mapped cache and Fully Associative cache.

## Cache / Memory Details:

a. L1 Data Cache - 32 KB. 

b. Cache Block Size - 64 bytes. 

c. Memory- 64 KB. 

d. Cache <-> Memory Bus width - 64 bits. 

e. Memory Bus Speed - 200 MHz. 

Both caches connect to the same 64 KB backing memory model (implemented using Block RAM ip) and are write back in nature, burst fills/writebacks are (8 x 64 bit beats per 64 byte line), and a fixed line size of 64 B. 

Two testbenches drive row major and column major matrix walks, measure misses, hits, writebacks, and compute bus traffic between cache and memory.

The row and column major loops are as follows:

<img width="214" height="68" alt="image" src="https://github.com/user-attachments/assets/8e2911b5-1e97-488a-ba9d-05145c1c5c6b" />
<img width="214" height="68" alt="image" src="https://github.com/user-attachments/assets/0e2fc256-fcdf-4fa6-8e34-c6d9e497b4e7" />


#  Direct Mapped cache
<img width="691" height="471" alt="dm_cache" src="https://github.com/user-attachments/assets/3d18ad31-618e-4bd8-b781-0f24aad33b52" />

Direct-Mapped Cache (32x32 matrix size):
<img width="1027" height="251" alt="result_128" src="https://github.com/user-attachments/assets/a3195faf-3650-4e38-af73-527f36237c37" />

Direct-Mapped Cache (128x128 matrix size):
<img width="1039" height="248" alt="result_32" src="https://github.com/user-attachments/assets/d6863239-a858-407d-8940-fbaa58a85746" />

# Fully Associative cache
<img width="862" height="769" alt="cache_FA" src="https://github.com/user-attachments/assets/b885310d-60df-4e02-a0c9-de382714c9da" />

Fully Associative Cache with Random Replacement (32x32 matrix size):
<img width="1006" height="257" alt="result_32" src="https://github.com/user-attachments/assets/6bec2652-9f49-4e49-8580-72e05f5c8054" />

Fully Associative Cache with Random Replacement (128x128 matrix size):
<img width="1024" height="212" alt="result_128" src="https://github.com/user-attachments/assets/f8fd1332-b792-41cc-8eaf-64328693db5e" />

Fully Associative Cache with LRU Replacement (128x128 matrix size):
<img width="1089" height="216" alt="result_128" src="https://github.com/user-attachments/assets/a913b974-1a44-4695-a6a5-b8fc98611e73" />

# Number of Misses
<img width="650" height="307" alt="image" src="https://github.com/user-attachments/assets/4d614d4b-7d78-40ce-bb27-bb8ab4c873d8" />
