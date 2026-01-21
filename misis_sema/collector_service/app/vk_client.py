import vk_api
import re

class VKClient:
    def __init__(self, token: str):
        self.vk_session = vk_api.VkApi(token=token)
        self.vk = self.vk_session.get_api()

    def wall_get_batch(self, owner_id_or_domain, offset: int):
        """
        owner_id_or_domain:
          - int / "123" / "-123" -> wall.get(owner_id=...)
          - "club123"/"public123"/"event123" -> wall.get(owner_id=-123)
          - "feivt" / "vk.com/feivt" -> wall.get(domain="feivt")
        Параметр domain у wall.get — это как раз короткий адрес. [web:21]
        """
        v = owner_id_or_domain

        # 1) если int
        if isinstance(v, int):
            return self.vk.wall.get(owner_id=-abs(v), count=100, offset=offset, extended=0)

        s = str(v).strip()
        if not s:
            raise ValueError("owner_id/domain is empty")

        # 2) ссылка -> берём хвост
        s = s.replace("https://vk.com/", "").replace("http://vk.com/", "").replace("vk.com/", "")
        s = s.strip().strip("/")

        # 3) строка-число -> owner_id
        if re.fullmatch(r"-?\d+", s):
            return self.vk.wall.get(owner_id=-abs(int(s)), count=100, offset=offset, extended=0)

        # 4) "club123"/"public123"/"event123" -> owner_id
        m = re.fullmatch(r"(?:club|public|event)(\d+)", s)
        if m:
            return self.vk.wall.get(owner_id=-abs(int(m.group(1))), count=100, offset=offset, extended=0)

        # 5) иначе это короткое имя (domain)
        return self.vk.wall.get(domain=s, count=100, offset=offset, extended=0)
