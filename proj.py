import random
import math
import matplotlib.pyplot as plt # type: ignore
from collections import deque
import time

class VideoField:
    """代表視訊欄位的類別"""
    def __init__(self, arrival_time: float, is_top: bool, complexity: float):
        self.arrival_time: float = arrival_time  # 到達時間
        self.is_top: bool = is_top             # 是否為上欄位
        self.complexity: float = complexity      # 複雜度(fobs)
        self.encoding_completion_time: float = 0 # 編碼完成時間

class VideoStorageSimulation:
    def __init__(self, buffer_size, sim_duration, tau, h, alpha, C_enc, C_storage):
        # 系統參數
        self.buffer_size = buffer_size    # 緩衝區大小(β)
        self.sim_duration = sim_duration  # 模擬時間(秒)
        self.tau = tau                    # 欄位間到達時間的參數
        self.h = h                        # 複雜度參數
        self.alpha = alpha                # 影格大小轉換係數
        self.C_enc = C_enc               # 編碼器容量(fobs/sec)
        self.C_storage = C_storage       # 儲存伺服器容量(bytes/sec)
        
        # 系統狀態
        self.current_time = 0            # 目前時間
        self.encoder_buffer: deque[VideoField] = deque()    # 編碼器緩衝區
        self.storage_queue: deque[VideoField] = deque()     # 儲存佇列
        self.is_storage_server_busy = False  # 儲存伺服器狀態
        self.next_field_is_top = True    # 下一個欄位是否為上欄位
        
        # 統計計數器
        self.total_frames: int = 0            # 總影格數
        self.lost_frames: int = 0             # 遺失影格數
        self.storage_busy_time: float = 0       # 儲存伺服器忙碌時間
        self.last_storage_state_change: float = 0  # 上次儲存狀態改變時間
        self.skip_next_field: bool = False     #判斷是否跳過下個FIELD
        
        # 事件佇列
        self.event_queue = []  # (時間, 事件類型, 額外資料)
        
    def generate_interarrival_time(self):
        """產生指數分佈的欄位間到達時間"""
        return -math.log(1 - random.random()) * self.tau
    
    def generate_complexity(self):
        """產生指數分佈的複雜度"""
        return -math.log(1 - random.random()) * self.h
    
    def schedule_event(self, time, event_type, data=None):
        """排程新事件"""
        self.event_queue.append((time, event_type, data))
        self.event_queue.sort()  # 依時間排序
        
    def handle_field_arrival(self):
        """處理欄位到達事件"""
        # 無論如何都要排程下一個到達
        next_arrival = self.current_time + self.generate_interarrival_time()
        self.schedule_event(next_arrival, "field_arrival")
        
        new_field = VideoField(
            self.current_time,
            self.next_field_is_top,
            self.generate_complexity()
        )
        
        # 檢查緩衝區空間
        if len(self.encoder_buffer) >= self.buffer_size:
            if new_field.is_top:
                self.lost_frames += 1  # 只計算當前欄位
                self.skip_next_field = True  # 標記下一個要跳過
            else:
                if not self.skip_next_field:
                    self.lost_frames += 1  # 因為上一個top被丟棄而跳過
                    self.skip_next_field = False
                else:
                    if self.encoder_buffer:
                        self.encoder_buffer.pop()  # 移除前一個上欄位
                        self.lost_frames += 1      # 計算被移除的欄位
                    self.lost_frames += 1          # 計算當前下欄位
        else:
            if not new_field.is_top and not self.skip_next_field:
                self.lost_frames += 1
                self.skip_next_field = False
            else:
                self.encoder_buffer.append(new_field)
                if len(self.encoder_buffer) == 1:
                    encoding_time = new_field.complexity / self.C_enc
                    new_field.encoding_completion_time = self.current_time + encoding_time
                    self.schedule_event(new_field.encoding_completion_time, "encoding_completion")
        
        self.next_field_is_top = not self.next_field_is_top
        
    def handle_encoding_completion(self):
        """處理編碼完成事件"""
        # 將編碼完成的欄位移至儲存佇列
        completed_field = self.encoder_buffer.popleft()
        self.storage_queue.append(completed_field)
        
        # 檢查是否可以開始儲存
        self.check_storage_start()
        
        # 如果緩衝區還有欄位，開始編碼下一個
        if self.encoder_buffer:
            next_field = self.encoder_buffer[0]
            encoding_time = next_field.complexity / self.C_enc
            next_field.encoding_completion_time = self.current_time + encoding_time
            self.schedule_event(next_field.encoding_completion_time, "encoding_completion")
            
    def check_storage_start(self):
        """檢查是否可以開始儲存影格"""
        if len(self.storage_queue) >= 2 and not self.is_storage_server_busy:
            # 確認有一對欄位(上和下)
            if self.storage_queue[0].is_top and not self.storage_queue[1].is_top:
                self.start_frame_storage()
                
    def start_frame_storage(self):
        """開始儲存影格"""
        # 取得一對欄位
        top_field = self.storage_queue.popleft()
        bottom_field = self.storage_queue.popleft()
        
        # 計算儲存時間
        frame_size = self.alpha * (top_field.complexity + bottom_field.complexity)
        storage_time = frame_size / self.C_storage
        
        # 更新統計資料
        self.is_storage_server_busy = True
        self.total_frames += 1
        
        # 記錄開始忙碌的時間
        self.last_storage_state_change = self.current_time
        
        # 排程儲存完成事件
        self.schedule_event(self.current_time + storage_time, "storage_completion")
        
    def handle_storage_completion(self):
        """處理儲存完成事件"""
        # 更新忙碌時間
        self.storage_busy_time += (self.current_time - self.last_storage_state_change)
        
        # 更新儲存伺服器狀態
        self.is_storage_server_busy = False
        self.last_storage_state_change = self.current_time
        
        # 檢查是否可以開始下一個儲存
        self.check_storage_start()
        
    def run(self):
        """執行模擬"""
        print(f"\nSimulation started - Buffer Size: {self.buffer_size}")
        print("="*50)
        start_time = time.time()
        # 初始化第一個事件
        self.schedule_event(0, "field_arrival")
        last_report_time = 0
        report_interval = 3600
        # 主要模擬迴圈
        while self.event_queue and self.current_time < self.sim_duration:
            # 取得下一個事件
            self.current_time, event_type, _ = self.event_queue.pop(0)
            if self.current_time - last_report_time >= report_interval:
                hour = self.current_time / 3600
                print(f"\nProgress at {hour:.1f} hours:")
                print(f"Lost Fields: {self.lost_frames}")
                print(f"Stored Frames: {self.total_frames}")
                print(f"Buffer Usage: {len(self.encoder_buffer)}/{self.buffer_size}")
                print(f"Storage Queue: {len(self.storage_queue)}")
                last_report_time = self.current_time
            # 處理事件
            if event_type == "field_arrival":
                self.handle_field_arrival()
            elif event_type == "encoding_completion":
                self.handle_encoding_completion()
            elif event_type == "storage_completion":
                self.handle_storage_completion()
            else:
                assert False
                
        # 計算最終統計資料
        if self.is_storage_server_busy:
            self.storage_busy_time += (self.sim_duration - self.last_storage_state_change)
            
    def get_results(self):
        """取得模擬結果"""
        # 計算影格遺失率
        total_fields = int(self.sim_duration / self.tau)  # 總共應該收到的欄位數
    
        # 計算遺失率
        frame_loss_ratio = self.lost_frames / total_fields if total_fields > 0 else 0
        
        # 計算儲存伺服器使用率
        storage_utilization = self.storage_busy_time / self.sim_duration
        print("\nFinal Results:")
        print(f"Total Fields Expected: {total_fields}")
        print(f"Lost Fields: {self.lost_frames}")
        print(f"Frames Stored: {self.total_frames}")
        print(f"Loss Ratio: {frame_loss_ratio:.4f}")
        print(f"Storage Utilization: {storage_utilization:.4f}")
        print("-"*50)
        return frame_loss_ratio, storage_utilization
# 執行模擬並繪製圖表的函數
def run_simulations():
    # 模擬參數
    sim_duration = 8 * 3600  # 8小時
    tau = 1/240             # 欄位間到達時間參數
    h = 400                 # 複雜度參數
    alpha = 0.1            # 影格大小轉換係數
    C_enc = 15800          # 編碼器容量
    C_storage = 1600       # 儲存伺服器容量
    buffer_sizes = [20, 40, 60, 80, 100]  # β值
    
    # 儲存結果
    loss_ratios = []
    utilizations = []
    start_time = time.time()
    # 對每個緩衝區大小執行模擬
    for buffer_size in buffer_sizes:
        sim = VideoStorageSimulation(
            buffer_size, sim_duration, tau, h, alpha, C_enc, C_storage
        )
        sim.run()
        loss_ratio, utilization = sim.get_results()
        loss_ratios.append(loss_ratio)
        utilizations.append(utilization)
    print(f"\nTotal simulation time: {time.time() - start_time:.2f} seconds")
        
    # 繪製圖表
    plt.figure(figsize=(12, 5))
    
    # 影格遺失率圖表
    plt.subplot(1, 2, 1)
    plt.plot(buffer_sizes, loss_ratios, 'bo-')
    plt.xlabel('Buffer Size (β)')
    plt.ylabel('Frame Loss Ratio (f)')
    plt.title('Frame Loss Ratio vs Buffer Size')
    plt.grid(True)
    plt.ylim(0.8, 1.0)
    # 儲存伺服器使用率圖表
    plt.subplot(1, 2, 2)
    plt.plot(buffer_sizes, utilizations, 'ro-')
    plt.xlabel('Buffer Size (β)')
    plt.ylabel('Storage Server Utilization (u)')
    plt.title('Storage Server Utilization vs Buffer Size')
    plt.ylim(0.0, 2.0)
    plt.grid(True)
    
    plt.tight_layout()
    plt.savefig('result.png')
    plt.show()

if __name__ == "__main__":
    # 設定隨機數種子以確保結果可重現
    random.seed(42)
    # 執行模擬
    run_simulations()